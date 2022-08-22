from pickle import GLOBAL
from flask import Flask, render_template, request, redirect, url_for
from azure.cosmos import CosmosClient
from uuid import UUID, uuid4
from datetime import date, datetime
import json

import os
URL = os.environ['ACCOUNT_URI']
KEY = os.environ['ACCOUNT_KEY']

# set global user ID until user ID's are a thing
GLOBAL_USER_ID = 6

# set up cosmos db connection
DATABASE_NAME = 'BookJournal'
CONTAINER_NAME = 'JournalEntries'
cosmosClient = CosmosClient(URL, credential=KEY)
database = cosmosClient.get_database_client(DATABASE_NAME)
container = database.get_container_client(CONTAINER_NAME)

app = Flask(__name__)

class Entry:
    id = ""
    userid = "{}".format(GLOBAL_USER_ID)
    title = ""
    author = ""
    rating = 0
    dateRead = datetime.today()    

@app.route("/")
def index():
    jsonJournalEntries = container.query_items(
        query='SELECT * FROM c where c.userid="{}"'.format(GLOBAL_USER_ID),
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
        
        journalEntries.append(newEntry)

        print('Found one! - {}'.format(newEntry.title))

    print('Found {} journal entries in total'.format(len(journalEntries)))

    journalEntries.sort(key=lambda x: x.dateRead, reverse=True)

    return render_template('index.html', journalEntries=journalEntries)

@app.route("/add", methods=["POST"])
def add():
    newEntry = Entry()
    newEntry.id=uuid4().__str__()
    newEntry.title=request.form.get("title", "Unknown")
    newEntry.author=request.form.get("author", "Unknown")
    newEntry.rating=request.form.get("rating", 0)
    newEntry.dateRead=request.form.get("dateRead", "1990/1/1")
    

    container.upsert_item({
        'id': newEntry.id,
        'userid': newEntry.userid,
        'title': newEntry.title,
        'author': newEntry.author,
        'rating': newEntry.rating,
        'dateRead': newEntry.dateRead
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