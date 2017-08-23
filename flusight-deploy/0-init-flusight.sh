#!/usr/bin/env bash

# Script to downlaod and setup flusight directory structure
set -e

# Download flusight master
wget "https://github.com/reichlab/flusight/archive/master.zip"
unzip ./master.zip
rm ./master.zip

# Parse data model data files to flusight format
npm install
npm run parse-data
# Replace already present data
rm -rf ./flusight-master/data
mv ./data ./flusight-master

cd ./flusight-master
npm install
npm run get-actual
npm run parse
npm run test
cd .. # in flusight-deploy now
