#!/bin/bash

# Installe la CLI AWS v2 (le paquet snap suit les dernières versions, >= 2.32 requis pour "aws login")
sudo snap install aws-cli --classic
aws --version
