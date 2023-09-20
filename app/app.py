from flask import Flask
import datetime
app = Flask(__name__)
app.debug = True

@app.route("/")
def hello_world():
    # Get the current UTC time
    utc_time = datetime.datetime.now(datetime.timezone.utc)
    print("hi")
    # Format the UTC time as "Tue Sep 19 17:40:45 IST 2023"
    formatted_time = utc_time.strftime('%a %b %d %H:%M:%S %Y %Z')
    return formatted_time