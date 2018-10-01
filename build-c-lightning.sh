#!/bin/bash
git clone https://github.com/groestlcoin/lightning.git src/lightning
cd src/lightning
./configure
make
sudo make install
