#ifndef _MIMEPARSER_H_INCLUDED
#define _MIMEPARSER_H_INCLUDED

/**
 * Prototypes for functions used by the parser routines
 */
int 	count_lines(char *);
void	mimieparser_yyerror(const char *);
int 	dprintf(const char *, ...);
int 	mimeparser_yyparse(void);
int 	mimeparser_yylex(void);
int	mimeparser_yyerror(const char *);

struct s_position
{
	size_t opaque_start;
	size_t start;
	size_t end;
};

#endif /* ! _MIMEPARSER_H_INCLUDED */
