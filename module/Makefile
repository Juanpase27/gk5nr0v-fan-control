obj-m += gk5nr0v-fans.o

KDIR ?= /lib/modules/$(shell uname -r)/build

.PHONY: all clean install

all:
	make -C $(KDIR) M=$(CURDIR) modules

clean:
	make -C $(KDIR) M=$(CURDIR) clean

install: all
	install -D -m 644 gk5nr0v-fans.ko \
		$(DESTDIR)/lib/modules/$(shell uname -r)/extra/gk5nr0v-fans.ko
	depmod $(shell uname -r)
