#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/wait.h>
#include "mm.h"

static FILE *setup(char *argv[])
{
	int fds[2];
	int pid;
	FILE *fp;

	if (pipe(fds) == -1) {
		perror("pipe");
		exit(111);
	}

	switch ((pid = fork())) {
	case -1:
		perror("fork");
		exit(111);
	case 0:
		{
			if (fds[0] != 0) close(0);
			close(fds[1]);
			if (fds[0] != 0 && dup(fds[0]) != 0) exit(111);
			fcntl(0, F_SETFL, fcntl(0, F_GETFL) | 1);
			execvp(*argv,argv);
			exit(111);
		};
	};
	/* parent */
	close(fds[0]);
	fp = fdopen(fds[1], "w");
}

int main(int argc, char *argv[])
{
	MM_CTX *ctx;
	struct mm_mimeheader *header, *lastheader;
	struct mm_warning *warning, *lastwarning;
	struct mm_mimepart *part;
	struct mm_content *ct;
	FILE *out;
	int r, i, parts,st;

	mm_library_init();
	mm_codec_registerdefaultcodecs();
	if (argc <= 1 || isatty(0)) {
		fprintf(stderr, "Usage: mimepipe exe < /mime/message.eml\n");
		exit(1);
	}

	ctx = mm_context_new();
	if (mm_parse_seekable(ctx, stdin, MM_PARSE_LOOSE, 0) == -1
			|| mm_errno != MM_ERROR_NONE) {
		/* nada */
		fprintf(stderr, "%s\n", mm_error.error_msg);
		exit(1);
	}

	parts = mm_context_countparts(ctx);
	for (i = 1; i < mm_context_countparts(ctx); i++) {
		part = mm_context_getpart(ctx, i);
		out = setup(argv+1);
		r = mm_mimepart_decode_to(part, out);
		fflush(out);
		fclose(out);
		while (wait(&st) == -1);
		if (!r) continue;

		if (!WIFEXITED(st)) continue;
		switch (WEXITSTATUS(st)) {
		case 97: /* stop now */
			exit(111);
		case 100: /* stop now */
			exit(100);
		case 98: /* stop now */
			exit(0);
		case 99: /* stop now */
			exit(99);
		};
	}
	exit(0);
}
