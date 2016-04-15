.PHONY: deps .go

export GOPATH=$(shell pwd)/.go
ARCH := $(shell uname -m)
NAME=qp
VERSION=$(shell git describe --tags --dirty --always)
RPMVERSION=$(shell git describe --tags --dirty --always | tr - "~")
SRCS 	=	qp.go
AUX  	=	ChangeLog Makefile

all: build rpm

deps: .go

.go:
	go get -d .

version:
	$(info Version: $(VERSION))
	$(info RPM Version: $(RPMVERSION))

build: deps $(NAME)

$(NAME): $(SRCS)
	go build -ldflags "-X main.version $(VERSION)" $(SRCS)

clean:
	rm -rf .go .rpmbuild
	rm -f $(NAME)-*.rpm
	rm -f $(NAME)

fmt:
	go fmt *.go

test: qp
	./tests/test.sh

unittest: qp
	go test .

tar: $(SRCS) $(AUX)
	rm -rf .tmp.dir
	mkdir .tmp.dir
	rm -f $(NAME)-$(VERSION).src.tar.gz
	for X in $(SRCS) $(AUX) ; do \
		echo $$X ; \
		cp $$X .tmp.dir/$$X ; done

$(NAME)-$(VERSION)-1.$(ARCH).rpm:
	rm -rf .rpmbuild
	mkdir -p .rpmbuild/{RPMS,SRPMS,BUILD,SOURCES,SPECS,tmp}
	echo "%_topdir   $(shell pwd)/.rpmbuild" > ~/.rpmmacros
	echo "%_tmppath  %{_topdir}/tmp" >> ~/.rpmmacros
	cat spec.spec | sed -e "s/__NAME__/$(NAME)/g" | sed -e "s/__RPMVERSION__/$(RPMVERSION)/g" > .rpmbuild/SPECS/$(NAME)-$(RPMVERSION).spec
	mkdir -p $(NAME)-$(RPMVERSION)/usr/bin
	install -m 755 $(NAME) $(NAME)-$(RPMVERSION)/usr/bin
	tar -zcvf $(NAME)-$(RPMVERSION).tar.gz $(NAME)-$(RPMVERSION)
	rm -rf $(NAME)-$(RPMVERSION)
	mv $(NAME)-$(RPMVERSION).tar.gz .rpmbuild/SOURCES/
	cd .rpmbuild && rpmbuild -ba SPECS/$(NAME)-$(RPMVERSION).spec
	find .rpmbuild/ -type f -name "*[^src].rpm" | xargs cp -t .
	mv $(NAME)-$(RPMVERSION)* `ls $(NAME)-$(RPMVERSION)* | tr "~" -`

rpm: $(NAME) $(NAME)-$(VERSION)-1.$(ARCH).rpm
