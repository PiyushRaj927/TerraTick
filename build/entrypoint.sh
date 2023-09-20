#!/usr/bin/env

cp -R /terratick /tmp/build
cd /tmp/build
python -m venv build # zappa requires a virtual env
. build/bin/activate 
ls -alh ./build/bin
pip install -r requirements.txt
zappa package dev -o dev.zip
cp dev.zip /terratick/dev.zip
