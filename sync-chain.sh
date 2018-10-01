#!/bin/bash

echo "Mount shared drive if needed..."
if ! df -h | grep /shared ; then
  export USER_ID=`id -u`
  export GROUP_ID=`id -g`
  sudo mount -t vboxsf -o umask=0022,gid=$GROUP_ID,uid=$USER_ID shared ~/shared
fi

if ! which groestlcoind ; then
  if [ ! -d src/groestlcoin-local ]; then
    echo "Installing Groestlcoin Core on this VM..."
    git clone https://github.com/groestlcoin/groestlcoin.git src/groestlcoin-local
    pushd src/groestlcoin-local
      git checkout 2.16.3
      # TODO: check git hash
      ./autogen.sh
      ./configure --disable-tests --disable-bench --disable-wallet --without-gui
      make
      echo "Sudo password required to finish install:"
      sudo make install
    popd
  else
    echo "Previous installation attempt failed?"
    exit 1
  fi
fi

groestlcoind -daemon -datadir=`pwd`/shared/groestlcoin

echo "Waiting for chain to catch up..."
OPTS=-datadir=`pwd`/shared/groestlcoin
set -o pipefail
while sleep 60
do
  if BLOCKHEIGHT=`groestlcoin-cli $OPTS getblockchaininfo | jq '.blocks'`; then
    if groestlcoin-cli $OPTS getblockchaininfo | jq -e '.initialblockdownload==false'; then
      echo "Almost caught up, wait 15 minutes..."
      sleep 900
      do # Wait for shutdown
        if [ ! -f ~/.groestlcoin/groestlcoind.pid ] && [ ! -f ~/.groestlcoin/testnet3/groestlcoind.pid ]; then
          break
        fi
      done
      break
    else
      echo "At block $BLOCKHEIGHT..."
    fi
  fi
done
