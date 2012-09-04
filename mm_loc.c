#include <stdlib.h>

#include "mm.h"

void mm_loc_free(struct mm_loc *p)
{
	if (p && p->text) xfree(p->text);
	if (p) xfree(p);
}

struct mm_loc *mm_loc_new_literal(char *s, unsigned int len)
{
	struct mm_loc *p;
	p = malloc(sizeof(struct mm_loc));
	if (p == NULL) return p;
	p->off = -1;
	p->text = s;
	p->fp = NULL;
	p->len = len;
	return p;
}
char *mm_loc_string(struct mm_loc *p)
{
	fpos_t fp;
	char *x;

	if (!p->len) return "";

	if (p->fp) {
		x = (char*)xmalloc(p->len);

		fgetpos(p->fp, &fp);
		fseek(p->fp, p->off, SEEK_SET);
		if (fread(x, p->len, 1, p->fp) != 1) return x; /* err... */
		fsetpos(p->fp, &fp);

		p->text = x;
		p->fp = NULL;
	}

	if (p->text) return p->text;
}
FILE *mm_loc_reader(struct mm_loc *p)
{
	if (!p->fp) return NULL;
	fgetpos(p->fp, &p->pos);
	fseek(p->fp, p->off, SEEK_SET);
	return p->fp;
}
void mm_loc_donereading(struct mm_loc *p)
{
	fsetpos(p->fp, &p->pos);
}


