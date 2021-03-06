#!/bin/bash
CONFIG_FLAGS=" --disable-tests --disable-bench --enable-glibc-back-compat --enable-reduce-exports LDFLAGS=-static-libstdc++"
USE_DEPENDS=0
GUI=0
BITS=64
LIGHTNING=
GROESTLCOIN_DATADIR=shared/groestlcoin
PREBUILT_GROESTLCOIN_CORE=0
PARALLEL=1
ARMBIAN_CLEAN_LEVEL=make,debs
UBUNTU=bionic
TIMEZONE=UTC
LOCALE=en_US

while getopts ":hcgdl:b:pj:u:t:a:" opt; do
  case $opt in
    h)
      echo "Usage: ./armbian-groestlcoin-core/prepare-build.sh -b 32 [options] tag"
      echo "  options:"
      echo "  -h     Print this message"
      echo "  -b     Bits: 32 or 64 (default)"
      echo "  -g     Build GUI (QT)"
      echo "  -j     Number of parallel threads to use during build (each needs ~1.5 GB RAM)"
      # echo "  -t   Use testnet" # TODO
      # echo "  -..." override groestlcoin datadir
      # echo "  -d     Use depends"
      echo "  -l [c] Add lightning: c (c-lightning)"
      echo "  -p     Use pre-built groestlcoin core binaries in src/groestlcoin"
      echo "  -c     Clean"
      echo "  -u     Ubuntu release: bionic (18.04, default)"
      echo "  -t     Set timezone (e.g. \"Europe/Amsterdam\", default: UTC)"
      echo "  -a     Set locale (default: en_US)"
      exit 0
      ;;
    b)
      if [ $OPTARG == "32" ]; then
        BITS=32
      elif [ $OPTARG == "64" ]; then
        BITS=64
      else
        echo "Bits should be 32 or 64"
        exit 1
      fi
      ;;
    g)
      GUI=1
      ;;
    d)
      USE_DEPENDS=1
      ;;
    l)
      if [ $OPTARG == "c" ]; then
        LIGHTNING=c
      else
        echo "Invalid choice for Lightning: $OPTARG (use 'c')"
        exit 1
      fi
      ;;
    p)
      PREBUILT_GROESTLCOIN_CORE=1
      ;;
    j)
      PARALLEL=$OPTARG
      ;;
    c)
      if [ -d src/groestlcoin ]; then
      echo "Cleaning groestlcoin dir..."
        pushd src/groestlcoin
          make distclean
          pushd depends
            make clean-all
          popd
        popd
      fi
      if [ -d build ]; then
        echo "Telling Armbian to clean more..."
        ARMBIAN_CLEAN_LEVEL=make,alldebs,cache,extras # ,sources
      fi
      ;;
    u)
      if [ $OPTARG == "bionic" ]; then
        UBUNTU=bionic
      else
        echo "Ubuntu should be '-u bionic'"
        exit 1
      fi
      ;;
    t)
      TIMEZONE=$OPTARG
      ;;
    a)
      LOCALE=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

shift $((OPTIND-1))

if [ "$PREBUILT_GROESTLCOIN_CORE" -eq "0" ]; then
  if [ -z "$1" ]; then
    echo "Specify release tag, e.g.: .previous_release 2.19.1"
    exit 1
  fi
fi

# TODO: skip stuff if it's already done

echo "If asked, enter your sudo password in order to upgrade your system, install dependencies and mount shared folder..."
sudo apt-get update

echo "Installing dependencies..."
sudo apt-get install -y automake autotools-dev libtool g++-aarch64-linux-gnu \
             g++-arm-linux-gnueabihf pkg-config ccache curl build-essential \
             linux-headers-`uname -r` jq

echo "Check if guest editions are installed..."
if ! lsmod | grep vboxguest ; then
  read -p "Insert Guest Editions CD and press enter"
  if [ ! -d /media/cdrom ]; then
    sudo mkdir --p /media/cdrom
    sudo mount -t auto /dev/cdrom /media/cdrom/
    sudo /media/cdrom/./VBoxLinuxAdditions.run
  fi

  echo "Installed guest editions. Please reboot and run this script again."
  exit 0
fi

echo "Mount shared drive if needed..."
if ! df -h | grep /shared ; then
  export USER_ID=`id -u`
  export GROUP_ID=`id -g`
  mkdir -p ~/shared
  sudo mount -t vboxsf -o umask=0022,gid=$GROUP_ID,uid=$USER_ID shared ~/shared
fi

# TODO: check ~/shared/groestlcoin/blocks and ~/shared/groestlcoin/chainstate exist

if [ "$PREBUILT_GROESTLCOIN_CORE" -eq "0" ]; then
  if [ ! -d src/groestlcoin ]; then
    git clone https://github.com/groestlcoin/groestlcoin.git src/groestlcoin
  fi
  pushd src/groestlcoin
    git reset --hard
    git checkout $1
    pushd depends
      if [ "$BITS" -eq "32" ]; then
        if [ "$GUI" -eq "0" ]; then
          make HOST=arm-linux-gnueabihf NO_QT=1 -j$PARALLEL
        else
          make HOST=arm-linux-gnueabihf -j$PARALLEL
        fi
      else
        if [ "$GUI" -eq "0" ]; then
          make HOST=aarch64-linux-gnu NO_QT=1 -j$PARALLEL
        else
          make HOST=aarch64-linux-gnu -j$PARALLEL
        fi
      fi
    popd
    ./autogen.sh
    if [ "$BITS" -eq "32" ]; then
      ./configure $CONFIG_FLAGS --prefix=$PWD/depends/arm-linux-gnueabihf
    else
      ./configure $CONFIG_FLAGS --prefix=$PWD/depends/aarch64-linux-gnu
    fi
    make -j$PARALLEL
  popd
fi

if [ "$GUI" -eq "0" ]; then
  echo "Check if groestlcoin binaries are present..."
  FILES="groestlcoin-cli groestlcoind"

  for f in $FILES;
  do
    if [ ! -f src/groestlcoin/src/$f ]; then
      echo "Could not find $f in src/groestlcoin/src"
      exit 1
    fi
  done
fi



# TODO: can't cross compile c-lightning yet
# if [ "$LIGHTNING" -eq "c" ]; then

if [ ! -d build ]; then
  echo "Cloning Armbian and adding patches..."
  git clone https://github.com/armbian/build.git
  mkdir -p build/userpatches/overlay/bin
  mkdir -p build/userpatches/overlay/scripts
fi

cp armbian-groestlcoin-core/customize-image.sh build/userpatches
cp armbian-groestlcoin-core/lib.config build/userpatches
cp armbian-groestlcoin-core/build-c-lightning.sh build/userpatches/overlay/scripts
cp armbian-groestlcoin-core/first_boot.service build/userpatches/overlay/scripts
cp armbian-groestlcoin-core/first_boot_desktop.service build/userpatches/overlay/scripts

sed -i "s:UTC:$TIMEZONE:" build/userpatches/overlay/scripts/first_boot.service
sed -i "s/en_US/$LOCALE/" build/userpatches/overlay/scripts/first_boot.service

if [ "$GUI" -eq "1" ]; then
  # Use Rocket wallapper from https://flic.kr/p/221H7xu, get rid of second workspsace
  # and use slightly larger icon:
  cp armbian-groestlcoin-core/rocket.jpg build/userpatches/overlay
  cp armbian-groestlcoin-core/xfce4-desktop.xml build/userpatches/overlay
  cp armbian-groestlcoin-core/lightdm-gtk-greeter.conf build/userpatches/overlay
  cp armbian-groestlcoin-core/keyboard.desktop build/userpatches/overlay
fi

if [ "$LIGHTNING" == "c" ]; then
  echo 'PACKAGE_LIST_ADDITIONAL="$PACKAGE_LIST_ADDITIONAL autoconf libtool libgmp-dev libsqlite3-dev python python3 net-tools zlib1g-dev"' >> build/userpatches/lib.config

  echo "./tmp/overlay/scripts/build-c-lightning.sh" >> build/userpatches/customize-image.sh
fi

# Copy groestlcoin configuration
rm -rf build/userpatches/overlay/groestlcoin
mkdir -p build/userpatches/overlay/groestlcoin
cp armbian-groestlcoin-core/groestlcoin.conf build/userpatches/overlay/groestlcoin
echo "lang=$LOCALE" >> build/userpatches/overlay/groestlcoin/groestlcoin.conf

# Copy binaries to the right place:
cp src/groestlcoin/src/groestlcoind src/groestlcoin/src/groestlcoin-cli build/userpatches/overlay/bin
if [ "$GUI" -eq "1" ]; then
  cp src/groestlcoin/src/qt/groestlcoin-qt build/userpatches/overlay/bin
fi

# Copy block index and chainstate:
# mkdir build/userpatches/overlay/groestlcoin/testnet3
cp -r $GROESTLCOIN_DATADIR/blocks build/userpatches/overlay/groestlcoin
# cp -r $GROESTLCOIN_DATADIR/testnet3/blocks build/userpatches/overlay/groestlcoin/testnet3
cp -r $GROESTLCOIN_DATADIR/chainstate build/userpatches/overlay/groestlcoin
# cp -r $GROESTLCOIN_DATADIR/testnet3/chainstate build/userpatches/overlay/groestlcoin/testnet3

pushd build
  if [ "$GUI" -eq "0" ]; then
    BUILD_DESKTOP=no
  else
    BUILD_DESKTOP=yes
  fi
  # DISPLAY_MANAGER=lightdm takes too long
  ./compile.sh CLEAN_LEVEL=$ARMBIAN_CLEAN_LEVEL RELEASE=$UBUNTU BUILD_DESKTOP=$BUILD_DESKTOP KERNEL_ONLY=no KERNEL_CONFIGURE=no PRIVATE_CCACHE=yes
popd
