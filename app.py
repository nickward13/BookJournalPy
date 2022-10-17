from pickle import GLOBAL
from flask import Flask, render_template, request, redirect, url_for, session
from flask_session import Session
from azure.cosmos import CosmosClient
from uuid import UUID, uuid4
from datetime import date, datetime
import json
import msal
import app_config

# for App Insights
import logging
from opencensus.ext.azure.log_exporter import AzureLogHandler
from opencensus.ext.azure.trace_exporter import AzureExporter
from opencensus.ext.flask.flask_middleware import FlaskMiddleware
from opencensus.trace.samplers import ProbabilitySampler

import os
URL = os.environ['ACCOUNT_URI']
KEY = os.environ['ACCOUNT_KEY']
APPLICATIONINSIGHTS_CONNECTION_STRING = os.environ['APPLICATIONINSIGHTS_CONNECTION_STRING']

logger = logging.getLogger(__name__)
logger.addHandler(AzureLogHandler(connection_string=APPLICATIONINSIGHTS_CONNECTION_STRING))

# set global user ID until user ID's are a thing
GLOBAL_USER_ID = 6

# set up cosmos db connection
DATABASE_NAME = 'BookJournal'
CONTAINER_NAME = 'JournalEntries'
cosmosClient = CosmosClient(URL, credential=KEY)
database = cosmosClient.get_database_client(DATABASE_NAME)
container = database.get_container_client(CONTAINER_NAME)

# set up app
app = Flask(__name__)
middleware = FlaskMiddleware(
    app,
    exporter=AzureExporter(connection_string=APPLICATIONINSIGHTS_CONNECTION_STRING),
    sampler=ProbabilitySampler(rate=1.0)
)
app.config.from_object(app_config)
Session(app)

class Entry:
    id = ""
    userid = "{}".format(GLOBAL_USER_ID)
    title = ""
    author = ""
    rating = 0
    dateRead = datetime.today()
    comments = ""   

# This section is needed for url_for("foo", _external=True) to automatically
# generate http scheme when this sample is running on localhost,
# and to generate https scheme when it is deployed behind reversed proxy.
# See also https://flask.palletsprojects.com/en/1.0.x/deploying/wsgi-standalone/#proxy-setups
from werkzeug.middleware.proxy_fix import ProxyFix
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)

@app.route("/")
def index():
    if not session.get("user"):
        session["flow"] = _build_auth_code_flow(scopes=app_config.SCOPE)
        logger.warning('No user logged in.')
        return render_template('index.html', auth_url=session["flow"]["auth_uri"], version=msal.__version__, APPLICATIONINSIGHTS_CONNECTION_STRING=APPLICATIONINSIGHTS_CONNECTION_STRING)
    else:
        user=session["user"]
        logger.warning('User logged in with ID: "{}"'.format(user["oid"]))
        
        jsonJournalEntries = container.query_items(
            query='SELECT * FROM c where c.userid="{}"'.format(user["oid"]),
            enable_cross_partition_query=False
        )

        journalEntries = []

        for jsonEntry in jsonJournalEntries:
            
            dictEntry = json.loads(json.dumps(jsonEntry))
            
            newEntry = Entry()
            newEntry.id = dictEntry.get('id', "Unknown")
            newEntry.userid = dictEntry.get("userid", "Unknown")
            newEntry.title = dictEntry.get("title", "Unknown")
            newEntry.author = dictEntry.get("author", "Unknown")
            newEntry.rating = dictEntry.get("rating", 0)
            newEntry.dateRead = dictEntry.get("dateRead", "1990/1/1")
            newEntry.comments = dictEntry.get("comments", None)
            
            journalEntries.append(newEntry)

            logger.warning('Found one! - {}'.format(newEntry.title))

        logger.warning('Found {} journal entries in total'.format(len(journalEntries)))

        journalEntries.sort(key=lambda x: x.dateRead, reverse=True)

        return render_template('index.html', journalEntries=journalEntries, user=user, version=msal.__version__, APPLICATIONINSIGHTS_CONNECTION_STRING=APPLICATIONINSIGHTS_CONNECTION_STRING)


@app.route("/add", methods=["POST"])
def add():
    user=session["user"]
    
    newEntry = Entry()
    newEntry.id=uuid4().__str__()
    newEntry.userid="{}".format(user["oid"])
    newEntry.title=request.form.get("title", "Unknown")
    newEntry.author=request.form.get("author", "Unknown")
    newEntry.rating=request.form.get("rating", 0)
    newEntry.dateRead=request.form.get("dateRead", "1990/1/1")
    newEntry.comments=request.form.get("comments", "")

    container.upsert_item({
        'id': newEntry.id,
        'userid': newEntry.userid,
        'title': newEntry.title,
        'author': newEntry.author,
        'rating': newEntry.rating,
        'dateRead': newEntry.dateRead,
        'comments': newEntry.comments
        }
    )
    return redirect(url_for("index"))

@app.route("/delete")
def delete():
    entryId = request.args.get('id', None)
    entryUserid = request.args.get('userid', None)
    for entry in container.query_items(
        query='SELECT * FROM c WHERE c.userid="{}" AND c.id="{}"'.format(entryUserid, entryId),
        enable_cross_partition_query=False
    ):
        container.delete_item(entry, partition_key='{}'.format(entryUserid))
        return redirect(url_for("index"))

@app.route("/login")
def login():
    # Technically we could use empty list [] as scopes to do just sign in,
    # here we choose to also collect end user consent upfront
    session["flow"] = _build_auth_code_flow(scopes=app_config.SCOPE)
    return render_template("login.html", auth_url=session["flow"]["auth_uri"], version=msal.__version__, APPLICATIONINSIGHTS_CONNECTION_STRING=APPLICATIONINSIGHTS_CONNECTION_STRING)

@app.route(app_config.REDIRECT_PATH)  # Its absolute URL must match your app's redirect_uri set in AAD
def authorized():
    try:
        cache = _load_cache()
        result = _build_msal_app(cache=cache).acquire_token_by_auth_code_flow(
            session.get("flow", {}), request.args)
        if "error" in result:
            return render_template("auth_error.html", result=result, APPLICATIONINSIGHTS_CONNECTION_STRING=APPLICATIONINSIGHTS_CONNECTION_STRING)
        session["user"] = result.get("id_token_claims")
        _save_cache(cache)
    except ValueError:  # Usually caused by CSRF
        pass  # Simply ignore them
    return redirect(url_for("index"))

@app.route("/logout")
def logout():
    session.clear()  # Wipe out user and its token cache from session
    return redirect(  # Also logout from your tenant's web session
        app_config.AUTHORITY + "/oauth2/v2.0/logout" +
        "?post_logout_redirect_uri=" + url_for("index", _external=True))

def _load_cache():
    cache = msal.SerializableTokenCache()
    if session.get("token_cache"):
        cache.deserialize(session["token_cache"])
    return cache

def _save_cache(cache):
    if cache.has_state_changed:
        session["token_cache"] = cache.serialize()

def _build_msal_app(cache=None, authority=None):
    return msal.ConfidentialClientApplication(
        app_config.CLIENT_ID, authority=authority or app_config.AUTHORITY,
        client_credential=app_config.CLIENT_SECRET, token_cache=cache)

def _build_auth_code_flow(authority=None, scopes=None):
    return _build_msal_app(authority=authority).initiate_auth_code_flow(
        scopes or [],
        redirect_uri=url_for("authorized", _external=True))

app.jinja_env.globals.update(_build_auth_code_flow=_build_auth_code_flow)  # Used in template

if __name__ == '__main__':
   app.run()
