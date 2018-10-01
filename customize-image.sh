#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
#
# This is the image customization script

# NOTE: It is copied to /tmp directory inside the image
# and executed there inside chroot environment
# so don't reference any files that are not already installed

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

# TODO: exit with non-zero status if anything goes wrong

sudo -s <<'EOF'
  # User with sudo rights and initial password:
  useradd groestlcoin -m -s /bin/bash --groups sudo
  echo "groestlcoin:groestlcoin" | chpasswd
  echo "groestlcoin ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/groestlcoin
EOF

# TODO copy ssh pubkey if found, disable password SSH login

# Clone Groestlcoin Core repo for graphics assets and (if needed) compilation:
sudo -s <<'EOF'
  git clone https://github.com/groestlcoin/groestlcoin.git /usr/local/src/groestlcoin
  cd /usr/local/src/groestlcoin
  git checkout 2.16.3
  # TODO: check signature commit hash
EOF

if [ "$BUILD_DESKTOP" == "yes" ]; then
  sudo -s <<'EOF'
    sudo add-apt-repository ppa:groestlcoin/groestlcoin
    sudo apt-get update
    sudo apt-get install -y libdb5.3-dev libdb5.3++-dev
    # apt enters a confused state, perform incantation and try again:
    sudo apt-get -y -f install
    sudo apt-get install -y libdb5.3-dev libdb5.3++-dev
EOF
fi

if [ -f /tmp/overlay/bin/groestlcoind ]; then
  sudo cp /tmp/overlay/bin/groestlcoin* /usr/local/bin
  if [ -f /tmp/overlay/bin/groestlcoin-qt ] && [ "$BUILD_DESKTOP" == "yes" ]; then
    sudo cp /tmp/overlay/bin/groestlcoin-qt /usr/local/bin
  fi
elif [ "$BUILD_DESKTOP" == "yes" ]; then
  sudo -s <<'EOF'
    cd /usr/local/src/groestlcoin
    ./autogen.sh
    if ! ./configure --disable-tests --disable-bench --with-qrencode --with-gui=qt5 ; then
      exit 1
    fi
    make
    make install
EOF
fi

# Configure Groestlcoin Core:
sudo -s <<'EOF'
  mkdir /home/groestlcoin/.groestlcoin
  mkdir /home/groestlcoin/.groestlcoin/wallets
  cp /tmp/overlay/groestlcoin/groestlcoin.conf /home/groestlcoin/.groestlcoin

  # TODO: offer choice between mainnet and testnet
  # echo "testnet=1" >> /home/groestlcoin/.groestlcoin/groestlcoin.conf
  # mkdir /home/groestlcoin/.groestlcoin/testnet3

  # Copy block index and chain state from host:
  cp -r /tmp/overlay/groestlcoin/chainstate /home/groestlcoin/.groestlcoin
  cp -r /tmp/overlay/groestlcoin/blocks /home/groestlcoin/.groestlcoin

  # cp -r /tmp/overlay/groestlcoin/testnet3/chainstate /home/groestlcoin/.groestlcoin/testnet3
  # cp -r /tmp/overlay/groestlcoin/testnet3/blocks /home/groestlcoin/.groestlcoin/testnet3

  chown -R groestlcoin:groestlcoin /home/groestlcoin/.groestlcoin
EOF

# Install Tor
sudo -s <<'EOF'
  if ! su - groestlcoin -c "gpg --keyserver pgp.surfnet.nl --recv A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89" ; then
    if ! su - groestlcoin -c "gpg --keyserver pgp.mit.edu --recv A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89" ; then
      exit 1
    fi
  fi
  su - groestlcoin -c "gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89" | apt-key add -
cat <<EOT >> /etc/apt/sources.list
deb https://deb.torproject.org/torproject.org bionic main
deb-src https://deb.torproject.org/torproject.org bionic main
EOT
  apt-get update
  apt-get install -y tor deb.torproject.org-keyring
  mkdir -p /usr/share/tor
cat <<EOT >> /usr/share/tor/tor-service-defaults-torrc
ControlPort 9051
CookieAuthentication 1
CookieAuthFileGroupReadable 1
EOT
  usermod -a -G debian-tor groestlcoin
EOF

cp /tmp/overlay/scripts/first_boot.service /etc/systemd/system
systemctl enable first_boot.service

if [ "$BUILD_DESKTOP" == "yes" ]; then
  # Groestlcoin desktop background and icon:
  sudo -s <<'EOF'
    apt remove -y nodm
    apt-get install -y lightdm lightdm-gtk-greeter xfce4 onboard

    cp /tmp/overlay/rocket.jpg /usr/share/backgrounds/xfce/rocket.jpg
    mkdir -p /home/groestlcoin/.config/xfce4/xfconf/xfce-perchannel-xml
    cp /tmp/overlay/xfce4-desktop.xml /home/groestlcoin/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
    cp /tmp/overlay/lightdm-gtk-greeter.conf /etc/lightdm/lightdm-gtk-greeter.conf
    mkdir -p /home/groestlcoin/Desktop
    mkdir -p /home/groestlcoin/.config/autostart
    cp /usr/local/src/groestlcoin/contrib/debian/bitcoin-qt.desktop /home/groestlcoin/Desktop
    chmod +x /home/groestlcoin/Desktop/bitcoin-qt.desktop
    cp /tmp/overlay/keyboard.desktop /home/groestlcoin/.config/autostart
    chown -R groestlcoin:groestlcoin /home/groestlcoin/Desktop
    chown -R groestlcoin:groestlcoin /home/groestlcoin/.config
    cp /usr/local/src/groestlcoin/share/pixmaps/bitcoin128.png /usr/share/pixmaps
    cp /usr/local/src/groestlcoin/share/pixmaps/bitcoin256.png /usr/share/pixmaps
    cp /tmp/overlay/scripts/first_boot_desktop.service /etc/systemd/system
    systemctl enable first_boot_desktop.service
    systemctl set-default graphical.target
EOF
fi
