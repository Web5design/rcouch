BASE_DIR         = $(shell pwd)
REBAR           ?= $(BASE_DIR)/rebar
OVERLAY_VARS    ?=
ERLANG_BIN       = $(shell dirname $(shell which erl))
WITHOUT_CURL?=1

REPO			?= rcouch
PKG_REVISION	?= $(shell git describe ==tags)
PKG_BUILD		= 1

$(if $(ERLANG_BIN),,$(warning "Warning: No Erlang found in your path, this will probably not work"))


.PHONY: rel deps

all: deps compile

compile:
	@WITHOUT_CURL=$(WITHOUT_CURL) $(REBAR) compile

deps:
	@$(REBAR) get-deps

clean:
	@$(REBAR) clean

distclean: clean relclean
	@$(REBAR) delete-deps

generate:
	@WITHOUT_CURL=$(WITHOUT_CURL) $(REBAR) generate $(OVERLAY_VARS)

rel: relclean compile generate

relclean:
	@rm -rf rel/rcouch


ARCH= $(shell uname -m)


# Tag from git with style <tagname>-<commits_since_tag>-<current_commit_hash>
# Ex: When on a tag:            riak-1.0.3   (no commits since tag)
#     For most normal Commits:  riak-1.1.0pre1-27-g1170096
#                                 Last tag:          riak-1.1.0pre1
#                                 Commits since tag: 27
#                                 Hash of commit:    g1170096
#
REPO_TAG 	:= $(shell git describe --tags)

# Split off repo name
# Changes to 1.0.3 or 1.1.0pre1-27-g1170096 from example above
REVISION = $(shell echo $(REPO_TAG) | sed -e 's/^$(REPO)-//')

# Primary version identifier, strip off commmit information
# Changes to 1.0.3 or 1.1.0pre1 from example above
MAJOR_VERSION	?= $(shell echo $(REVISION) | sed -e 's/\([0-9.]*\)-.*/\1/')

##
## release tarballs
##

# Use git archive to copy a repository at a current revision to a new directory
archive_git = git archive --format=tar --prefix=$(1)/ HEAD | (cd $(2) && tar xf -)

# Checkout tag, fetch deps (so we don't have to do it multiple times) and collect
# the version of all the dependencies into the MANIFEST_FILE
CLONEDIR ?= rcouch-clone
MANIFEST_FILE ?= dependency_manifest.git
get_dist_deps = mkdir distdir && \
                git clone . distdir/$(CLONEDIR) && \
                cd distdir/$(CLONEDIR) && \
                git checkout $(REPO_TAG) && \
                $(MAKE) deps && \
                echo "- Dependencies and their tags at build time of $(REPO) at $(REPO_TAG)" > $(MANIFEST_FILE) && \
                for dep in deps/*; do \
                    cd $${dep} && \
                    printf "$${dep} version `git describe --long --tags 2>/dev/null || git rev-parse HEAD`\n" >> ../../$(MANIFEST_FILE) && \
                    cd ../..; done && \
                LC_ALL=POSIX && export LC_ALL && sort $(MANIFEST_FILE) > $(MANIFEST_FILE).tmp && mv $(MANIFEST_FILE).tmp $(MANIFEST_FILE);

# Name resulting directory & tar file based on current status of the git tag
# If it is a tagged release (PKG_VERSION == MAJOR_VERSION), use the toplevel
#   tag as the package name, otherwise generate a unique hash of all the
#   dependencies revisions to make the package name unique.
#   This enables the toplevel repository package to change names
#   when underlying dependencies change.
NAME_HASH = $(shell git hash-object distdir/$(CLONEDIR)/$(MANIFEST_FILE) 2>/dev/null | cut -c 1-8)
ifeq ($(REVISION), $(MAJOR_VERSION))
PKG_ID := $(REPO_TAG)
else
PKG_ID = $(REPO)-$(MAJOR_VERSION)-$(NAME_HASH)
endif

# To ensure a clean build, copy the CLONEDIR at a specific tag to a new directory
#  which will be the basis of the src tar file (and packages)
# The vsn.git file is required by rebar to be able to build from the resulting
#  tar file
build_clean_dir = cd distdir/$(CLONEDIR) && \
                  $(call archive_git,$(PKG_ID),..) && \
                  cp $(MANIFEST_FILE) ../$(PKG_ID)/ && \
                  mkdir ../$(PKG_ID)/deps && \
                  for dep in deps/*; do \
                      cd $${dep} && \
                      $(call archive_git,$${dep},../../../$(PKG_ID)) && \
                      mkdir -p ../../../$(PKG_ID)/$${dep}/priv && \
                      printf "`git describe --long --tags 2>/dev/null || git rev-parse HEAD`" > ../../../$(PKG_ID)/$${dep}/priv/vsn.git && \
                      cd ../..; done


distdir/$(CLONEDIR)/$(MANIFEST_FILE):
	$(if $(REPO_TAG), $(call get_dist_deps), $(error "You can't generate a release tarball from a non-tagged revision. Run 'git checkout <tag>', then 'make dist'"))

distdir/$(PKG_ID): distdir/$(CLONEDIR)/$(MANIFEST_FILE)
	$(call build_clean_dir)

distdir/$(PKG_ID).tar.gz: distdir/$(PKG_ID)
	tar -C distdir -czf distdir/$(PKG_ID).tar.gz $(PKG_ID)

dist: distdir/$(PKG_ID).tar.gz
	cp distdir/$(PKG_ID).tar.gz .

ballclean:
	rm -rf $(PKG_ID).tar.gz distdir

pkgclean: ballclean
	rm -rf package

##
## Packaging targets
##

# Yes another variable, this one is repo-<generatedhash
# which differs from $REVISION that is repo-<commitcount>-<commitsha>
PKG_VERSION = $(shell echo $(PKG_ID) | sed -e 's/^$(REPO)-//')

package: distdir/$(PKG_ID).tar.gz
	ln -s distdir package
	$(MAKE) -C package -f $(PKG_ID)/deps/node_package/Makefile

.PHONY: package
export PKG_VERSION PKG_ID PKG_BUILD BASE_DIR ERLANG_BIN REBAR OVERLAY_VARS RELEASE
