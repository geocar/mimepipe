%{
/*
 * Copyright (c) 2004 Jann Fischer. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/**
 * This is a lexer file for parsing MIME compatible messages. It is intended
 * to satisfy at least RFC 2045 (Format of Internet Message Bodies). It still
 * has quite a few problems:
 *
 *	- The parsing could probably be done in a more elegant way
 *	- I don't know what performance impact REJECT has on the parser
 */
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>

#include "mimeparser.h"

#include "mimeparser.tab.h"


/* BC() is a debug wrapper for lex' BEGIN() macro */
#define BC(x) do { \
	dprintf("Entering condition %d (%s) at line %d (in %d)\n", x, #x, lineno,__LINE__); \
	BEGIN(x); \
	condition = x; \
} while(0);

#define ZERO(x) memset(x, '\0', sizeof(x))

#define PREALLOC_BUFFER	100000

enum header_states
{
	STATE_MAIL = 0,
	STATE_CTYPE,
	STATE_CDISP,
	STATE_CENC,
	STATE_MIME
};

int header_state = STATE_MAIL;
int lineno = 0;
size_t current_pos = 1;
int condition = 0;

int is_envelope = 1;

extern int mime_parts;
extern char *boundary_string;
extern char *endboundary_string;

extern const char *message_buffer;

size_t message_len = 0;
size_t buffer_length = 0;

/* temporary marker variables */
size_t body_opaque_start = 0;
size_t body_start = 0;
size_t body_end = 0;
size_t preamble_start = 0;
size_t postamble_start = 0;
size_t postamble_end = 0;

%}

%s headers
%s header
%s headervalue
%s tspecialvalue
%s comment
%s body
%s postamble
%s preamble
%s boundary
%s endboundary
%s endoffile

STRING	[a-zA-Z0-9\-\.\_]
TSPECIAL [a-zA-Z0-9)(<>@,;:/\-.=_\+'? ]
TSPECIAL_LITE [a-zA-Z0-9)(<>@,-._+'?\[\]]

%%

<INITIAL,headers>^[a-zA-Z]+[a-zA-Z0-9\-\_]* {
	mimeparser_yylval.string=strdup(yytext); 
	current_pos += yyleng;
	BC(header);
	dprintf("seeing header: %s\n", yytext);

	/* Depending on what header we are processing, we enter a different
	 * state and return a different value.
	 */
	if (!strcasecmp(yytext, "Content-Type")) {
		header_state = STATE_CTYPE;
		return CONTENTTYPE_HEADER;
	} else if (!strcasecmp(yytext, "Content-Transfer-Encoding")) {
		header_state = STATE_CENC;
		return CONTENTENCODING_HEADER;
	} else if (!strcasecmp(yytext, "Content-Disposition")) {
		header_state = STATE_CDISP;
		return CONTENTDISPOSITION_HEADER;
	} else if (!strcasecmp(yytext, "MIME-Version")) {
		header_state = STATE_MAIL;
		return MIMEVERSION_HEADER;
	} else {
		header_state = STATE_MAIL;
		return MAIL_HEADER;
	}
}

<INITIAL,headers>. {
	dprintf("Unknown header char: %c\n", *yytext);
	current_pos += yyleng;
	return ANY;
}

<headers>^(\r\n|\n) {
	lineno++; 
	dprintf("END OF HEADERS\n");

	current_pos += yyleng;

	/* This marks the end of headers. Depending on whether we are in the
	 * envelope currently we need to parse either a body or the preamble
	 * now.
	 */
	if (is_envelope == 0 || boundary_string == NULL) {
		dprintf("BODY! at %d\n", current_pos);
		BC(body);
		body_start = current_pos;
	} else {
		dprintf("PREAMBLE at %d\n",current_pos);
		is_envelope = 0;
		preamble_start = current_pos;
		BC(preamble);
	}	

	return ENDOFHEADERS;
}

<header>\: {
	dprintf("COLON\n");
	BC(headervalue); 
	current_pos += yyleng;
	return COLON;
}	

<header>(\r\n|\n) {
	BC(headers);
	dprintf("Invalid header, passing up\n");
	yyless(0);
}	

<headervalue>.+|(.+(\r\n|\n)[\ \t]+.+)+ {
	if (header_state != STATE_MAIL && header_state != STATE_CENC) {
		REJECT;
	}
	dprintf("MAIL HEADER VALUE:%s\n", yytext);
	current_pos += yyleng;
	while (*yytext && isspace(*yytext)) yytext++;
	/* Do we actually have a header value? */
	if (*yytext == '\0') {
		mimeparser_yylval.string = strdup("");
	} else {
		mimeparser_yylval.string=strdup(yytext); 
		lineno += count_lines(yytext);
	}	
	return WORD;
}

<headervalue,tspecialvalue>(\r\n|\n) {
	/* marks the end of one header line */
	lineno++;
	dprintf("EOL\n");
	BC(headers);
	current_pos += yyleng;
	return EOL;
}

<headervalue>;|;(\r\n|\n)[\ \t]+ {
	dprintf("SEMICOLON\n");
	lineno += count_lines(yytext);
	current_pos += yyleng;
	return SEMICOLON;
}

<headervalue>\= {
	current_pos += yyleng;
	return EQUAL;
}

<headervalue>\" {
	BC(tspecialvalue);
	current_pos += yyleng;
	return *yytext;
}

<headervalue>{STRING}+|{TSPECIAL_LITE}+ {
	dprintf("W: %s\n", yytext);
	mimeparser_yylval.string=strdup(yytext);
	lineno += count_lines(yytext);
	current_pos += yyleng;
	return WORD;
}

<headervalue>[\ \t]+	{
	current_pos += yyleng;
}	

<tspecialvalue>{TSPECIAL}+ {
	dprintf("T: %s\n", yytext);
	lineno += count_lines(yytext);
	mimeparser_yylval.string=strdup(yytext);
	current_pos += yyleng;
	return TSPECIAL;
}

<tspecialvalue>\" {
	BC(headervalue);
	current_pos += yyleng;
	return *yytext;
}

<body>^\-\-{TSPECIAL}+\-\- {
	/**
	 * Make sure we only catch matching boundaries, and not other lines
	 * that begin and end with two dashes. If we have catched a valid
	 * end boundary, which actually ends a body, we save the current
	 * position, put the token back on the input stream and let the
	 * endboundary condition parse the actual token.
	 */
	if (endboundary_string != NULL) {
		if (strcmp(endboundary_string, yytext)) {
			dprintf("YYTEXT != end_boundary: '%s'\n", yytext);
			REJECT;
		} else {
			dprintf("YYTEXT == end_boundary: '%s'\n", yytext);
			if (body_start) {
				dprintf("\tand saw body start\n");
				mimeparser_yylval.position.opaque_start = 
				    body_opaque_start;
				mimeparser_yylval.position.start = body_start;
				mimeparser_yylval.position.end = current_pos;
				body_opaque_start = 0;
				body_start = 0;
				body_end = 0;
				yyless(0); /* put yytext back */
				BC(endboundary);
				return BODY;
			}	
		}
	} else {
		dprintf("FOO!\n");
	}	

	REJECT;
}

<body,preamble>^\-\-{TSPECIAL}+ {
	/**
	 * Make sure we only catch matching boundaries, and not other lines
	 * that begin with two dashes.
	 */
	if (boundary_string != NULL) {
		if (strcmp(boundary_string, yytext)) {
			dprintf("YYTEXT != boundary: '%s'\n", yytext);
			REJECT;
		} else {
			dprintf("YYTEXT == boundary: '%s'\n", yytext);
			if (body_start) {
				mimeparser_yylval.position.opaque_start = body_opaque_start;
				mimeparser_yylval.position.start = body_start;
				mimeparser_yylval.position.end = current_pos-1;
				body_opaque_start = 0;
				body_start = 0;
				body_end = 0;
				yyless(0);
				BC(boundary);
				return BODY;
			} else if (preamble_start) {
				mimeparser_yylval.position.start = preamble_start;
				mimeparser_yylval.position.end = current_pos-1;
				preamble_start = 0;
				yyless(0);
				BC(boundary);
				return PREAMBLE;
			} else {
				dprintf("\twow, okay...\n");
				BC(boundary);
				mimeparser_yylval.string = strdup(yytext);
				current_pos += yyleng;
				return(BOUNDARY);
			}
		}
	} else {
		dprintf("FOO\n");
	}	

	REJECT;
}

<body>(\r\n|\n) {
	current_pos += yyleng;
	lineno++;
}

<body>\r {
	current_pos += yyleng;
	dprintf("stray CR in body...\n");
}

<body>[^\r\n]+ {
	current_pos += yyleng;
}

<body><<EOF>> {
	if (boundary_string == NULL && body_start) {
		mimeparser_yylval.position.opaque_start = 0;
		mimeparser_yylval.position.start = body_start;
		mimeparser_yylval.position.end = current_pos;
		body_start = 0;
		return BODY;
	} else if (body_start) {
		return POSTAMBLE;
	}	
	yyterminate();
}	

<preamble,postamble>(\r\n|\n) {
	dprintf("Preamble CR/LF at line %d\n", lineno);
	lineno++; 
	current_pos += yyleng;
}	

<boundary>[^\r\n]+ {
	mimeparser_yylval.string = strdup(yytext);
	dprintf("B: '%s'\n", yytext);
	current_pos += yyleng;
	return BOUNDARY;
}

<endboundary>[^\r\n]+ {
	mimeparser_yylval.string = strdup(yytext);
	dprintf("EB: %s\n", yytext);
	current_pos += yyleng;
	return ENDBOUNDARY;
}

<boundary>(\r\n|\n) {
	BC(headers);
	lineno++;
	dprintf("Boundary end of line: %d\n", lineno);
	current_pos += yyleng;
	body_opaque_start = current_pos;
	return EOL;
}

<endboundary>(\r\n|\n) {
	BC(postamble);
	lineno++;
	current_pos += yyleng;
	dprintf("Endboundary end of line\n");
}

<preamble>. {
	current_pos += yyleng;
}


<postamble>. {
	current_pos += yyleng;
}

(\r\n|\n) {
	lineno++;
	dprintf("End of header UNCLASSED!\n"); 
	current_pos += yyleng;
	return EOL;
}

. {
	dprintf("UC: '%c' in condition %d\n", *yytext, condition);
	if (condition == header) {
		dprintf("BROKEN PREAMBLE at %d\n",current_pos);
		is_envelope = 0;
		preamble_start = current_pos-1;
		BC(preamble);
		yyless(0);
		return ENDOFHEADERS;
	} else {
		current_pos += yyleng;
		return((int)*yytext);
	}
}


%%


void
PARSER_setbuffer(const char *string)
{
	message_buffer = string;
	yy_scan_string(string);
}

void
PARSER_setfp(FILE *fp)
{
	mimeparser_yyin = fp;
}

/**
 * Counts how many lines a given string represents in the message (in case of
 * folded header values, for example, or a message body).
 */
int
count_lines(char *txt)
{
	char *o;
	int line;

	line = 0;

	for (o = txt; *o != '\0'; o++)	
		if (*o == '\n')
			line++;

	return line;
}

