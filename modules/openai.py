#Note: The openai-python library support for Azure OpenAI is in preview.
import os
import openai
import modules.journal

openai.api_type = "azure"
openai.api_base = "https://hectagon-openai.openai.azure.com/"
openai.api_version = "2022-12-01"
openai.api_key = os.getenv("OPENAI_API_KEY")

def create_annual_review(journalEntries):

    prompt="You are a literary reviewer writing an end of year summary of the books you've read throughout the year. I will provide you with the list of books you've read along with when you read them and a rating out of 5 for how good you thought they were, with 1 being low and 5 being high.  Only include the books I've read below in the review.  Create a new paragraph for each book in the review. Here is the list of books you've read:\n\n"    # add each book to the prompt
    for entry in journalEntries:
        prompt += entry.title + " by " + entry.author + ", rated " + entry.rating + "/5\n\n"
    # add the end of the prompt
    prompt += "\n\nHere is the end of year summary:\n\n"

    response = openai.Completion.create(
    engine="davinci",
    prompt=prompt,
    temperature=1,
    max_tokens=1500,
    top_p=0.5,
    frequency_penalty=0,
    presence_penalty=0,
    best_of=1,
    stop=None)

    review = response["choices"][0]["text"]
    return review