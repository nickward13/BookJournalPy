# BookJournalPy
This project is a Python Flask web app for recording a book journal.  It uses an Azure Cosmos DB data store and is intended to be deployed to Azure using the main.bicep file in the azure folder.

## Virtual Environment
In addition to cloning the repo, a Python virtual environment is set up as per the [Flask installation instructions](https://flask.palletsprojects.com/en/2.2.x/installation/)

~~~
mkdir BookJournalPy
cd BookJournalPy
python3 -m venv venv
. venv/bin/activate
~~~

## Python Packages
The project requires the following Python packages:

~~~
    pip install Flask
    pip install azure-cosmos
~~~
