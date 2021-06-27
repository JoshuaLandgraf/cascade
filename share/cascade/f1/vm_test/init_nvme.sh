#!/bin/bash

echo "Creating XFS file system"
sudo mkfs.xfs /dev/nvme0n1

echo "Mounting file system"
sudo mkdir -p /mnt/nvme0
sudo mount -t xfs /dev/nvme0n1 /mnt/nvme0/

echo "Writing files"
sudo touch /mnt/nvme0/file0.bin
sudo touch /mnt/nvme0/file1.bin
sudo touch /mnt/nvme0/file2.bin
sudo touch /mnt/nvme0/file3.bin
sudo shred -n 1 -s 64G /mnt/nvme0/file0.bin &
sudo shred -n 1 -s 64G /mnt/nvme0/file1.bin &
sudo shred -n 1 -s 64G /mnt/nvme0/file2.bin &
sudo shred -n 1 -s 64G /mnt/nvme0/file3.bin &
wait

echo "Done"
