import os, json
from datetime import date, datetime
from pickle import GLOBAL
from azure.cosmos import CosmosClient
from uuid import UUID, uuid4

URL = os.environ['ACCOUNT_URI']
KEY = os.environ['ACCOUNT_KEY']

# set up cosmos db connection
DATABASE_NAME = 'BookJournal'
CONTAINER_NAME = 'JournalEntries'
cosmosClient = CosmosClient(URL, credential=KEY)
database = cosmosClient.get_database_client(DATABASE_NAME)
container = database.get_container_client(CONTAINER_NAME)

class Entry:
    id = ""
    userid = ""
    title = ""
    author = ""
    rating = 0
    dateRead = datetime.today()
    comments = ""   

def getEntries(userId):
    jsonJournalEntries = container.query_items(
            query='SELECT * FROM c where c.userid="{}"'.format(userId),
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

    journalEntries.sort(key=lambda x: x.dateRead, reverse=True)
    return journalEntries

def addEntry(newEntry):
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

def deleteEntry(entryId, entryUserid):
    for entry in container.query_items(
        query='SELECT * FROM c WHERE c.userid="{}" AND c.id="{}"'.format(entryUserid, entryId),
        enable_cross_partition_query=False
    ):
        container.delete_item(entry, partition_key='{}'.format(entryUserid))

def isAlive():
    for entry in container.query_items(
        query='SELECT VALUE COUNT(1) FROM c WHERE c.userid = "0"',
        enable_cross_partition_query=False
    ):
        return True
    
    return False