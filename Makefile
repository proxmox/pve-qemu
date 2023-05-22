include /usr/share/dpkg/default.mk

PACKAGE = pve-qemu-kvm

SRCDIR := qemu
BUILDDIR ?= ${PACKAGE}-${DEB_VERSION_UPSTREAM}
ORIG_SRC_TAR=$(PACKAGE)_$(DEB_VERSION_UPSTREAM).orig.tar.gz

GITVERSION := $(shell git rev-parse HEAD)

DSC=$(PACKAGE)_$(DEB_VERSION_UPSTREAM_REVISION).dsc
DEB = ${PACKAGE}_${DEB_VERSION_UPSTREAM_REVISION}_${DEB_BUILD_ARCH}.deb
DEB_DBG = ${PACKAGE}-dbg_${DEB_VERSION_UPSTREAM_REVISION}_${DEB_BUILD_ARCH}.deb
DEBS = $(DEB) $(DEB_DBG)

all: $(DEBS)

.PHONY: submodule
submodule:
	test -f "${SRCDIR}/configure" || git submodule update --init --recursive

$(BUILDDIR): keycodemapdb | submodule
	# check if qemu/ was used for a build
	# if so, please run 'make distclean' in the submodule and try again
	test ! -f $(SRCDIR)/build/config.status
	rm -rf $@.tmp $@
	cp -a $(SRCDIR) $@.tmp
	cp -a debian $@.tmp/debian
	rm -rf $@.tmp/ui/keycodemapdb
	cp -a keycodemapdb $@.tmp/ui/
	echo "git clone git://git.proxmox.com/git/pve-qemu.git\\ngit checkout $(GITVERSION)" > $@.tmp/debian/SOURCE
	mv $@.tmp $@

.PHONY: deb kvm
deb kvm: $(DEBS)
$(DEB_DBG): $(DEB)
$(DEB): $(BUILDDIR)
	cd $(BUILDDIR); dpkg-buildpackage -b -us -uc -j
	lintian $(DEBS)

sbuild: $(DSC)
	sbuild $(DSC)

$(ORIG_SRC_TAR): $(BUILDDIR)
	tar czf $(ORIG_SRC_TAR) --exclude="$(BUILDDIR)/debian" $(BUILDDIR)

.PHONY: dsc
dsc:
	rm -rf *.dsc $(BUILDDIR)
	$(MAKE) $(DSC)
	lintian $(DSC)

$(DSC): $(ORIG_SRC_TAR) $(BUILDDIR)
	cd $(BUILDDIR); dpkg-buildpackage -S -us -uc -d

.PHONY: update
update:
	cd $(SRCDIR) && git submodule deinit ui/keycodemapdb || true
	rm -rf $(SRCDIR)/ui/keycodemapdb
	mkdir $(SRCDIR)/ui/keycodemapdb
	cd $(SRCDIR) && git submodule update --init ui/keycodemapdb
	rm -rf keycodemapdb
	mkdir keycodemapdb
	cp -R $(SRCDIR)/ui/keycodemapdb/* keycodemapdb/
	git add keycodemapdb

.PHONY: upload
upload: UPLOAD_DIST ?= $(DEB_DISTRIBUTION)
upload: $(DEBS)
	tar cf - ${DEBS} | ssh repoman@repo.proxmox.com upload --product pve --dist $(UPLOAD_DIST)

.PHONY: distclean clean
distclean: clean
clean:
	rm -rf $(PACKAGE)-[0-9]*/ $(PACKAGE)*.tar* *.deb *.dsc *.build *.buildinfo *.changes

.PHONY: dinstall
dinstall: $(DEBS)
	dpkg -i $(DEBS)
