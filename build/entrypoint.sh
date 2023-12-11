#!/usr/bin/env bash
set -ex
cp -R /terratick /tmp/build
cd /tmp/build/client
npm install
npm run build 
cd ../
python -m venv venv # zappa requires a virtual env
. venv/bin/activate
pip install -r requirements.txt
cat zappa_settings.json
zappa package dev -o dev.zip
zip -ur dev.zip client/build
cp dev.zip /terratick/dev.zip
