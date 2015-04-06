SOURCES := $(wildcard src/*.litcoffee) $(wildcard src/adapters/*.litcoffee)
DOCS := $(patsubst src/%.litcoffee, docs/%.html, $(SOURCES))
JS := $(patsubst src/%.litcoffee, lib/%.js, $(SOURCES))

.PHONY: doc, lib

docs/%.html: src/%.litcoffee
	node_modules/.bin/docco -o $(@D) $^

lib/%.js: src/%.litcoffee
	coffee -c -o $(@D) $<

#sources.md: $(DOCS)
#	d
#	echo "

doc: $(DOCS)

lib: $(JS)
