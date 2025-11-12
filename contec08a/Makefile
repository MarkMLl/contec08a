# This is intended to build a text-only variant of the program in this directory, based on
# http://troydm.github.io/blog/2014/01/26/making-30-years-old-pascal-code-run-again/
# It probably won't attempt anything fancy like working out what revision the sources are
# which might result in warnings during compilation and possibly linkage, to do the
# whole job properly use lazbuild or the Lazarus IDE. MarkMLl.

# PREREQUISITE: FPC (Free Pascal Compiler), v2.6.0 but preferably v3.0.2 or above.

############

# FPCFLAGS can usefully be transcribed from the Lazarus IDE's "Show Options" output.

FPC=/usr/local/bin/fpc
FPCFLAGS=-O3 -CX -XX -k--build-id 
DEFINES=-dHAS_SVN -dHAS_FPC_SVN
INIFILES=../inifiles/trunk
SERIALCOMMS=../serialcomms/trunk
CPU=$(shell uname -m | sed 's/i686/i386/' | sed 's/armv7l/arm/')
OPSYS=$(shell uname -o | sed 's/GNU\/Linux/linux/')
FPCSrcDir=/usr/local/src/fpc/$(shell $(FPC) -iV)/compiler

# Note that the CPU identifier above loses potentially-useful information, but
# this was done in order to generate the same filenames emitted by Lazarus.

############

all: contec08a-$(CPU)-$(OPSYS)

# NOTE THAT THIS MIGHT ONLY BE A PARTIAL DEPENDENCY LIST.

$(INIFILES)/inifilesabout.o: Makefile project_svnrevision.inc fpc_svnrevision.inc $(INIFILES)/inifilesabout.pas

contec08a-$(CPU)-$(OPSYS): Makefile $(INIFILES)/inifilesabout.o $(SERIALCOMMS)/monitorhidlinux.pas consoleapp.pas contec08a.lpr 
	/bin/sh -c "echo -n C`svnversion -n`C |tr A-G %-+ >project_svnrevision.inc & echo -n C`svnversion -n $(FPCSrcDir)`C |tr A-G %-+>fpc_svnrevision.inc"
	$(FPC) $(FPCFLAGS) $(DEFINES) -Fu$(INIFILES) -Fu$(SERIALCOMMS) -Fu../common -ocontec08a-$(CPU)-$(OPSYS) contec08a.lpr 

############

clean:
	rm -f contec08a*.ppu contec08a*.o contec08a.or
	rm -f $(INIFILES)/inifilesabout.o $(INIFILES)/inifilesabout.ppu
	rm -f $(SERIALCOMMS)/monitorhidlinux.o $(SERIALCOMMS)/monitorhidlinux.ppu

distclean: clean
	rm -f contec08a-$(CPU)-$(OPSYS)

