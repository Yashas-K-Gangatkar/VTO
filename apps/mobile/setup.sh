#!/bin/bash
echo "Cleaning up..."
rm -rf node_modules
rm -f package-lock.json
rm -f .expo

echo "Installing dependencies..."
npm install

echo "Clearing cache and starting..."
npx expo start --clear
