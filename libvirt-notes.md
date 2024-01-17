# KVM/QEMU/Libvirt Virtualization Notes

## Windows 11

January 2024 - on newer Intel 13900K or my i9-14900K machine with performance
and efficiency cores there's a bug that results in Windows being stuck in
"Automatic Repair" loop on boot when host-passthrough or host-model are used as
the CPU. 

This fix will get you going, from:
https://github.com/tianocore/edk2/discussions/4662

    <cpu mode="custom" match="exact" check="none">
        <model fallback="forbid">qemu64</model>
        <maxphysaddr mode="passthrough"/>
    </cpu>

Alternatively, bypass libvirt and start up with a command extracted from a
running libvirt Windows 11 machine, with the relevant alteration:

/usr/bin/qemu-system-x86_64 -name guest=win11,debug-threads=on -S \
    -object {"qom-type":"secret","id":"masterKey0","format":"raw","file":"/var/lib/libvirt/qemu/domain-21-win11/master-key.aes"} \
    -blockdev {"driver":"file","filename":"/usr/share/qemu/edk2-x86_64-secure-code.fd","node-name":"libvirt-pflash0-storage","auto-read-only":true,"discard":"unmap"} \
    -blockdev {"node-name":"libvirt-pflash0-format","read-only":true,"driver":"raw","file":"libvirt-pflash0-storage"} \
    -blockdev {"driver":"file","filename":"/var/lib/libvirt/qemu/nvram/win11_VARS.fd","node-name":"libvirt-pflash1-storage","auto-read-only":true,"discard":"unmap"} \
    -blockdev {"node-name":"libvirt-pflash1-format","read-only":false,"driver":"raw","file":"libvirt-pflash1-storage"} \
    -machine pc-q35-8.1,usb=off,vmport=off,smm=on,dump-guest-core=off,memory-backend=pc.ram,pflash0=libvirt-pflash0-format,pflash1=libvirt-pflash1-format,hpet=off,acpi=on \
    -accel kvm \
    -cpu host,host-phys-bits-limit=0x28 \
-global driver=cfi.pflash01,property=secure,value=on \
-m size=16408576k \
-object {"qom-type":"memory-backend-ram","id":"pc.ram","size":16802381824} -overcommit mem-lock=off -smp 12,sockets=1,dies=1,cores=12,threads=1 -uuid 66b68919-83e3-4109-9f9f-df507567ad96 -no-user-config -nodefaults -chardev socket,id=charmonitor,fd=30,server=on,wait=off -mon chardev=charmonitor,id=monitor,mode=control -rtc base=localtime,driftfix=slew -global kvm-pit.lost_tick_policy=delay -no-shutdown -global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1 -boot strict=on -device {"driver":"pcie-root-port","port":16,"chassis":1,"id":"pci.1","bus":"pcie.0","multifunction":true,"addr":"0x2"} -device {"driver":"pcie-root-port","port":17,"chassis":2,"id":"pci.2","bus":"pcie.0","addr":"0x2.0x1"} -device {"driver":"pcie-root-port","port":18,"chassis":3,"id":"pci.3","bus":"pcie.0","addr":"0x2.0x2"} -device {"driver":"pcie-root-port","port":19,"chassis":4,"id":"pci.4","bus":"pcie.0","addr":"0x2.0x3"} -device {"driver":"pcie-root-port","port":20,"chassis":5,"id":"pci.5","bus":"pcie.0","addr":"0x2.0x4"} -device {"driver":"pcie-root-port","port":21,"chassis":6,"id":"pci.6","bus":"pcie.0","addr":"0x2.0x5"} -device {"driver":"pcie-root-port","port":22,"chassis":7,"id":"pci.7","bus":"pcie.0","addr":"0x2.0x6"} -device {"driver":"pcie-root-port","port":23,"chassis":8,"id":"pci.8","bus":"pcie.0","addr":"0x2.0x7"} -device {"driver":"pcie-root-port","port":24,"chassis":9,"id":"pci.9","bus":"pcie.0","multifunction":true,"addr":"0x3"} -device {"driver":"pcie-root-port","port":25,"chassis":10,"id":"pci.10","bus":"pcie.0","addr":"0x3.0x1"} -device {"driver":"pcie-root-port","port":26,"chassis":11,"id":"pci.11","bus":"pcie.0","addr":"0x3.0x2"} -device {"driver":"pcie-root-port","port":27,"chassis":12,"id":"pci.12","bus":"pcie.0","addr":"0x3.0x3"} -device {"driver":"pcie-root-port","port":28,"chassis":13,"id":"pci.13","bus":"pcie.0","addr":"0x3.0x4"} -device {"driver":"pcie-root-port","port":29,"chassis":14,"id":"pci.14","bus":"pcie.0","addr":"0x3.0x5"} -device {"driver":"qemu-xhci","p2":15,"p3":15,"id":"usb","bus":"pci.2","addr":"0x0"} -device {"driver":"virtio-serial-pci","id":"virtio-serial0","bus":"pci.3","addr":"0x0"} -netdev {"type":"tap","fd":"31","id":"hostnet0"} -device {"driver":"e1000e","netdev":"hostnet0","id":"net0","mac":"52:54:00:b9:52:82","bus":"pci.1","addr":"0x0"} -chardev pty,id=charserial0 -device {"driver":"isa-serial","chardev":"charserial0","id":"serial0","index":0} -chardev spicevmc,id=charchannel0,name=vdagent -device {"driver":"virtserialport","bus":"virtio-serial0.0","nr":1,"chardev":"charchannel0","id":"channel0","name":"com.redhat.spice.0"} -add-fd set=0,fd=36,opaque=tpm0-tpm -add-fd set=1,fd=37,opaque=tpm0-cancel -tpmdev passthrough,id=tpm-tpm0,path=/dev/fdset/0,cancel-path=/dev/fdset/1 -device {"driver":"tpm-crb","tpmdev":"tpm-tpm0","id":"tpm0"} -device {"driver":"usb-tablet","id":"input0","bus":"usb.0","port":"1"} -audiodev {"id":"audio1","driver":"spice"} -spice port=5900,addr=127.0.0.1,disable-ticketing=on,image-compression=off,seamless-migration=on -device {"driver":"qxl-vga","id":"video0","max_outputs":1,"ram_size":67108864,"vram_size":67108864,"vram64_size_mb":0,"vgamem_mb":16,"bus":"pcie.0","addr":"0x1"} -device {"driver":"ich9-intel-hda","id":"sound0","bus":"pcie.0","addr":"0x1b"} -device {"driver":"hda-duplex","id":"sound0-codec0","bus":"sound0.0","cad":0,"audiodev":"audio1"} -global ICH9-LPC.noreboot=off -watchdog-action reset -chardev spicevmc,id=charredir0,name=usbredir -device {"driver":"usb-redir","chardev":"charredir0","id":"redir0","bus":"usb.0","port":"2"} -chardev spicevmc,id=charredir1,name=usbredir -device {"driver":"usb-redir","chardev":"charredir1","id":"redir1","bus":"usb.0","port":"3"} -device {"driver":"vfio-pci","host":"0000:02:00.0","id":"hostdev0","bootindex":1,"bus":"pci.4","addr":"0x0"} -device {"driver":"vfio-pci","host":"0000:01:00.0","id":"hostdev1","bus":"pci.6","addr":"0x0"} -device {"driver":"vfio-pci","host":"0000:01:00.1","id":"hostdev2","bus":"pci.7","addr":"0x0"} -device {"driver":"virtio-balloon-pci","id":"balloon0","bus":"pci.5","addr":"0x0"} -sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny -msg timestamp=on


