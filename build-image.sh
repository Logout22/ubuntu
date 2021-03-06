#!/bin/bash -ex
### Build a docker image for ubuntu i386.

### settings
arch=i386
suite=${1:-trusty}
chroot_dir="/var/chroot/$suite"
apt_mirror='http://archive.ubuntu.com/ubuntu'
docker_image="32bit/ubuntu:${1:-14.04}"

function kill_safely() {
  kill $*
  sleep 2
  kill -9 $*
}

function unmount_system_folders() {
  ### disable immediate failure (while loop handles error case):
  set +e

  local safeguard=3
  while [ $(mount | grep -c $chroot_dir) -gt 0 ]; do
    ### kill any processes that are running on chroot
    chroot_pids=$(for p in /proc/*/root; do ls -l $p; done | grep $chroot_dir | cut -d'/' -f3)
    if ! [ -z "$chroot_pids" ]; then
      kill_safely $chroot_pids
    fi

    umount $chroot_dir/sys
    umount $chroot_dir/proc
    sleep 2

    safeguard=$[$safeguard-1]
    if [ $safeguard -eq 0 ]; then
      echo "Could not unmount drives; please clean up manually."
      exit 1
    fi
  done

  ### uncritical, and unlikely to fail, hence no -f:
  rm $chroot_dir/etc/resolv.conf

  set -e
}

function remove_chroot_dir() {
  rm -f ubuntu.tgz
  rm -rf $chroot_dir
}

function on_exit() {
  trap '' EXIT
  unmount_system_folders
  remove_chroot_dir
}

### setup exit hook
trap on_exit EXIT

### make sure that the required tools are installed
packages="debootstrap dchroot apparmor"
which docker || packages="$packages docker.io"
apt-get install -y $packages

### install a minbase system with debootstrap
export DEBIAN_FRONTEND=noninteractive
debootstrap --variant=minbase --arch=$arch $suite $chroot_dir $apt_mirror

### update the list of package sources
cat <<EOF > $chroot_dir/etc/apt/sources.list
deb $apt_mirror $suite main restricted universe multiverse
deb $apt_mirror $suite-updates main restricted universe multiverse
deb $apt_mirror $suite-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $suite-security main restricted universe multiverse
deb http://extras.ubuntu.com/ubuntu $suite main
EOF

### install ubuntu-minimal
cp /etc/resolv.conf $chroot_dir/etc/resolv.conf
mount --bind /proc $chroot_dir/proc
mount --bind /sys $chroot_dir/sys
chroot $chroot_dir apt-get update
chroot $chroot_dir apt-get -y upgrade
chroot $chroot_dir apt-get -y install ubuntu-minimal

### cleanup
chroot $chroot_dir apt-get autoclean
chroot $chroot_dir apt-get clean
chroot $chroot_dir apt-get autoremove
unmount_system_folders

### create a tar archive from the chroot directory
tar cfz ubuntu.tgz -C $chroot_dir .

### import this tar archive into a docker image:
cat ubuntu.tgz | docker import - $docker_image

# ### push image to Docker Hub
# docker push $docker_image
