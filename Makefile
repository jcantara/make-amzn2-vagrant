.DEFAULT_GOAL := vagrant
.PHONY: virtualbox vagrant clean

VBOX_VERSION := $(shell vboxmanage -v | cut -d'_' -f1)
LATEST_AMZN2_VDI := $(shell curl -sL "https://cdn.amazonlinux.com/os-images/latest/virtualbox/" | xmllint --html -xpath "//a[substring(@href, string-length(@href) - string-length('.vdi') +1) = '.vdi']/@href" - | cut -d'"' -f2)

clean:
	vboxmanage controlvm amzn2raw poweroff || true
	vboxmanage unregistervm amzn2raw -delete || true
	rm virtualbox/user-data || true
	rm virtualbox/seed.iso || true
	rm virtualbox/amzn2raw-virtualbox.vdi || true
	rm -rf virtualbox/amzn2raw || true
	vagrant box remove --all ./vagrant/amzn2base || true
	rm vagrant/amzn2base || true
	vagrant global-status --prune || true

virtualbox/user-data: virtualbox/user-data-no-keys
	cp virtualbox/user-data-no-keys virtualbox/user-data
	cat ~/.ssh/id_rsa.pub | sed 's/.*/  - &/' >> virtualbox/user-data

virtualbox/seed.iso: virtualbox/user-data virtualbox/meta-data
	cd virtualbox; genisoimage -output seed.iso -volid cidata -joliet -rock user-data meta-data

virtualbox/amzn2raw-virtualbox.vdi:
	test -f virtualbox/$(LATEST_AMZN2_VDI) || curl -L "https://cdn.amazonlinux.com/os-images/latest/virtualbox/$(LATEST_AMZN2_VDI)" --output virtualbox/$(LATEST_AMZN2_VDI)
	chmod -w virtualbox/$(LATEST_AMZN2_VDI)
	cp virtualbox/$(LATEST_AMZN2_VDI) virtualbox/amzn2raw-virtualbox.vdi
	chmod 664 virtualbox/amzn2raw-virtualbox.vdi

virtualbox/vboxguestadditions.iso:
	test -f virtualbox/vboxguestadditions.iso || curl -L "https://download.virtualbox.org/virtualbox/$(VBOX_VERSION)/VBoxGuestAdditions_$(VBOX_VERSION).iso" --output virtualbox/vboxguestadditions.iso

virtualbox/amzn2raw/amzn2raw.vbox: virtualbox/amzn2raw-virtualbox.vdi virtualbox/seed.iso virtualbox/vboxguestadditions.iso
	vboxmanage createvm --name amzn2raw --ostype "RedHat_64" --register --basefolder `pwd`/virtualbox
	vboxmanage modifyvm amzn2raw --ioapic on
	vboxmanage modifyvm amzn2raw --memory 2048 --vram 8
	vboxmanage modifyvm amzn2raw --nic1 nat
	vboxmanage storagectl amzn2raw --name "SATA Controller" --add sata --controller IntelAhci
	vboxmanage storageattach amzn2raw --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium `pwd`/virtualbox/amzn2raw-virtualbox.vdi
	vboxmanage storagectl amzn2raw --name "IDE Controller" --add ide --controller PIIX4
	vboxmanage storageattach amzn2raw --storagectl "IDE Controller" --port 1 --device 0 --type dvddrive --medium `pwd`/virtualbox/seed.iso
	vboxmanage storageattach amzn2raw --storagectl "IDE Controller" --port 1 --device 1 --type dvddrive --medium `pwd`/virtualbox/vboxguestadditions.iso
	vboxmanage modifyvm amzn2raw --boot1 dvd --boot2 disk --boot3 none --boot4 none
	vboxmanage modifyvm amzn2raw --natpf1 "guestssh,tcp,,2222,,22"
	sleep 5 # have had several strange occurrences where settings from above don't seem to be applied when running startvm below, waiting a few seconds for virtualbox to catch up addresses it
	vboxmanage startvm --type headless amzn2raw
	ssh -p 2222 -o 'ConnectionAttempts 300' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ec2-user@localhost -- "sudo yum -y update && sudo -b sh -c 'sleep 1; reboot' && exit" # update everything and reboot in case kernel updates
	sleep 15 # wait for reboot to have taken effect; this should better than a sleep but good enough for now
	ssh -p 2222 -o 'ConnectionAttempts 300' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ec2-user@localhost -- "sudo mkdir /media/iso && sudo mount /dev/sr1 /media/iso/ && sudo yum -y install kernel-devel && sudo /media/iso/VBoxLinuxAdditions.run && sudo umount /media/iso && sudo rm -rf /media/iso && sudo -b sh -c 'sleep 1; shutdown -h now' && exit"
	sleep 15 # wait for shutdown; this should be better than a sleep but good enough for now
	vboxmanage modifyvm amzn2raw --natpf1 delete "guestssh"
	vboxmanage storageattach amzn2raw --storagectl "IDE Controller" --port 1 --device 1 --type dvddrive --medium emptydrive
	vboxmanage storageattach amzn2raw --storagectl "IDE Controller" --port 1 --device 0 --type dvddrive --medium emptydrive # seed.iso only needed for initial boot to run cloud-init scripts

virtualbox: virtualbox/amzn2raw/amzn2raw.vbox

vagrant/amzn2base: virtualbox/amzn2raw/amzn2raw.vbox
	vagrant box remove --all ./vagrant/amzn2base || true
	rm vagrant/amzn2base || true
	cd vagrant; vagrant package --base amzn2raw --output amzn2base

vagrant: vagrant/amzn2base
