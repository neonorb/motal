# motal
Mish based on Buildroot.

# Installing
## Dependencies
Before building, you may require some of these packages:
* unzip

To build: `make`

To install to an IMG file: `./install.sh it.img`

To install to a disk (this will delete ALL data): `sudo ./install.sh /dev/sdx`. Alternativly, you can install it to the IMG file, and then `dd` it to a real disk.
