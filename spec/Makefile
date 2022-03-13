.PHONY: all clean view

all:
	asciidoctor-pdf twd.adoc

view: all
	xdg-open twd.pdf

clean:
	rm -f twd.pdf
