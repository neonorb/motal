CONFIG=BR2_DEFCONFIG=../main.config

all: build

.PHONY:
init: buildroot

.PHONY:
update:
	@cd buildroot/ && git pull

buildroot:
	@git clone git://git.buildroot.net/buildroot buildroot/

.PHONY:
clean:
	@if [ -d buildroot/ ]; then \
		make -s apply-config; \
		cd buildroot/; make -s clean; \
	fi

.PHONY:
build: buildroot apply-config
	@cd buildroot/ && make -s all # run builds

.PHONY:
config: buildroot apply-config
	@cd buildroot/ && make -s xconfig # run configure dialog
	@cd buildroot/ && make -s $(CONFIG) savedefconfig >/dev/null # retrieve changes made from dialog and store them into main.config

.PHONY:
apply-config: buildroot	
	@cd buildroot/ && make -s $(CONFIG) defconfig >/dev/null # loads config from main.config into Buildroot

.PHONY:
linux-config: buildroot apply-config
	@cd buildroot/ && make -s linux-xconfig # loads config from linux.config into Buildroot and runs configure dialog
	@cd buildroot/ && make -s linux-update-defconfig # retrive changes made from dialog and store them into linux.config
