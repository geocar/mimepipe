CFLAGS=-g

mimepipe: mimepipe.o mm_base64.o mm_codecs.o mm_contenttype.o \
mm_context.o mm_envelope.o mm_error.o mm_header.o mm_init.o \
mm_mem.o mm_mimepart.o mm_mimeutil.o mm_param.o mm_parse.o \
mm_util.o mm_warnings.o strlcat.o strlcpy.o mm_loc.o \
mimeparser.tab.o lex.mimeparser_yy.o

mimeparser.tab.h mimeparser.tab.c: mimeparser.y
	yacc -bmimeparser -pmimeparser_yy -d $<

lex.mimeparser_yy.c: mimeparser.l mimeparser.tab.h
	lex -Pmimeparser_yy $<

mm_parse.c: mimeparser.tab.h

clean:
	rm -f mimepipe lex.mimeparser_yy.c mimeparser.tab.[ch] *.o
