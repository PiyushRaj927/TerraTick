from flask import Flask,jsonify,send_from_directory
import time
app = Flask(__name__)
app.debug = True

@app.route("/api/unixtime")
def unixTIme():
    serverTime = {'unix_time': time.time()}
    return jsonify(serverTime)

@app.route('/<path:path>')
@app.route('/', defaults={'path': 'index.html'})
def assets(path):
    return send_from_directory('./client/build/', path)
