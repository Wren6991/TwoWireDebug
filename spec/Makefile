.PHONY: all clean view

all:
	@echo ":revnumber: $(shell git log -1 --pretty=%h)$(shell git diff --quiet && echo '-clean' || echo '-dirty')" > gitref.adoc
	asciidoctor-pdf twd.adoc

view: all
	xdg-open twd.pdf

clean:
	rm -f twd.pdf
