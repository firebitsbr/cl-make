# To use this file first define the following variables in your
# makefile and then include cl.mk.
#
# PACKAGE_NAME ------- The full name of the CL package
# PACKAGE_NICKNAME --- The nickname of the CL package
#                      (default: package name)
# PACKAGE_NAME_FIRST - The first package name to require
#                      (default: package name)
# BINS --------------- Names of binaries to build with buildapp
# TEST_ARTIFACTS ----- Name of dependencies for testing
# LISP_DEPS ---------- Packages require to build CL package
# TEST_LISP_DEPS ----- Packages require to build CL test package

.PHONY: check-testbot check clean more-clean real-clean

# Use buildapp as the lisp compiler.
LC ?= buildapp

# You can set this as an environment variable to point to an alternate
# quicklisp install location.  If you do, ensure that it ends in a "/"
# character, and that you use the $HOME variable instead of ~.
INSTDIR ?= /usr/synth
QUICK_LISP ?= $(INSTDIR)/quicklisp/

ifeq "$(wildcard $(QUICK_LISP)/setup.lisp)" ""
$(warning $(QUICK_LISP) does not appear to be a valid quicklisp install)
$(error Please point QUICK_LISP to your quicklisp installation)
endif

LISP_LIBS += $(PACKAGE_NAME)
LC_LIBS:=$(addprefix --load-system , $(LISP_LIBS))
LOADED_LIBS:=$(addprefix quicklisp/local-projects/, $(LISP_LIBS:=.loaded))

LISP_DEPS ?=				\
	$(wildcard *.lisp) 		\
	$(wildcard src/*.lisp)

# Flags to buildapp
LCFLAGS=--manifest-file system-index.txt \
	--asdf-tree quicklisp/dists/quicklisp/software

ifneq ($(LISP_STACK),)
LCFLAGS+= --dynamic-space-size $(LISP_STACK)
endif

# Default lisp to build manifest file.
LISP ?= ccl
ifneq (,$(findstring sbcl, $(LISP)))
ifeq ("$(SBCL_HOME)","")
LISP_HOME = SBCL_HOME=$(dir $(shell which $(LISP)))../lib/sbcl
endif
endif
ifneq (,$(findstring sbcl, $(LISP)))
LISP_FLAGS = --no-userinit --no-sysinit
else
LISP_FLAGS = --quiet --no-init
endif

all: $(addprefix bin/, $(BINS))

# In this target we require :$(PACKAGE_NAME_FIRST) instead of
# :$(PACKAGE_NAME) because the later may depend on the former causing
# an error if :$(PACKAGE_NAME_FIRST) is not found.
PACKAGE_NAME_FIRST ?= $(PACKAGE_NAME)
system-index.txt: qlfile
	$(LISP_HOME) $(LISP) $(LISP_FLAGS) --load $(QUICK_LISP)/setup.lisp \
		--eval '(pushnew (truename ".") ql:*local-project-directories*)' \
		--eval '(ql:quickload :qlot)' \
		--eval '(qlot:install :$(PACKAGE_NAME_FIRST))' \
		--eval '(qlot:quickload :$(PACKAGE_NAME_FIRST))' \
		--eval '(qlot:with-local-quicklisp (:$(PACKAGE_NAME_FIRST)) (ql:register-local-projects))' \
		--eval '#+sbcl (exit) #+ccl (quit)'

quicklisp/local-projects/%.loaded: | system-index.txt
	$(LISP_HOME) $(LISP) $(LISP_FLAGS) --load quicklisp/setup.lisp \
		--eval '(pushnew (truename ".") ql:*local-project-directories*)' \
		--eval '(ql:quickload :$(notdir $*))' \
		--eval "#+sbcl (exit) #+ccl (quit)"
	touch $@

bin/%: $(LISP_DEPS) $(LOADED_LIBS) system-index.txt
	CC=$(CC) $(LISP_HOME) LISP=$(LISP) $(LC) $(LCFLAGS) $(LC_LIBS) --output $@ --entry "$(PACKAGE_HICKNAME):$@"


# Test executable
TEST_LISP_DEPS ?= $(wildcard test/src/*.lisp)
TEST_LISP_LIBS += $(PACKAGE_NAME)-test
TEST_LC_LIBS:=$(addprefix --load-system , $(TEST_LISP_LIBS))
TEST_LOADED_LIBS:=$(addprefix quicklisp/local-projects/, $(TEST_LISP_LIBS:=.loaded))

bin/$(PACKAGE_NICKNAME)-test: $(TEST_LISP_DEPS) $(LISP_DEPS) $(TEST_LOADED_LIBS) system-index.txt
	CC=$(CC) $(LISP_HOME) LISP=$(LISP) $(LC) $(LCFLAGS) $(TEST_LC_LIBS) --output $@ --entry "$(PACKAGE_NICKNAME)-test:run-batch"

bin/$(PACKAGE_NICKNAME)-testbot: $(TEST_LISP_DEPS) $(LISP_DEPS) $(TEST_LOADED_LIBS) system-index.txt
	CC=$(CC) $(LISP_HOME) LISP=$(LISP) $(LC) $(LCFLAGS) $(TEST_LC_LIBS) --output $@ --entry "$(PACKAGE_NICKNAME)-test:run-testbot"


## Testing
TEST_ARTIFACTS ?=

check: bin/$(PACKAGE_NICKNAME)-test $(TEST_ARTIFACTS)
	@$<

check-testbot: bin/$(PACKAGE_NICKNAME)-testbot $(TEST_ARTIFACTS)
	@$<


## Interactive testing
SWANK_PORT ?= 4005
swank: quicklisp/setup.lisp
	$(LISP_HOME) $(LISP) $(LISP_FLAGS)			\
	--load $<						\
	--eval '(pushnew (truename ".") ql:*local-project-directories*)' \
	--eval '(ql:quickload :swank)'				\
	--eval '(ql:quickload :$(PACKAGE_NAME))'		\
	--eval '(in-package :$(PACKAGE_NAME))'		\
	--eval '(swank:create-server :port $(SWANK_PORT) :style :spawn :dont-close t)'

swank-test: quicklisp/setup.lisp $(TEST_ARTIFACTS)
	$(LISP_HOME) $(LISP) $(LISP_FLAGS)			\
	--load $<						\
	--eval '(pushnew (truename ".") ql:*local-project-directories*)' \
	--eval '(ql:quickload :swank)'				\
	--eval '(ql:quickload :$(PACKAGE_NAME))'		\
	--eval '(ql:quickload :$(PACKAGE_NAME)-test)'	\
	--eval '(in-package :$(PACKAGE_NAME)-test)'		\
	--eval '(swank:create-server :port $(SWANK_PORT) :style :spawn :dont-close t)'

clean:
	rm -f bin/$(PACKAGE_NICKNAME)-test bin/$(PACKAGE_NICKNAME)-testbot bin/clang-instrument
	rm -f $(TEST_ARTIFACTS)

more-clean: clean
	find . -type f -name "*.fasl" -exec rm {} \+
	find . -type f -name "*.lx32fsl" -exec rm {} \+
	find . -type f -name "*.lx64fsl" -exec rm {} \+

real-clean: more-clean
	find . -type f -name "*.loaded" -exec rm {} \+
	rm -f qlfile.lock system-index.txt
	rm -rf quicklisp
