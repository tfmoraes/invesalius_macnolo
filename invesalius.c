#include <libgen.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include<unistd.h>  
#define SIZE_OUTPUT 24

int main(int argc, char **argv) {
    char cwd[1024];
    char* dname = dirname(argv[0]);
    strcpy(cwd, dname);
    strcat(cwd, "/../Resources/app/");
    chdir(cwd);
    printf("Inside: %s\\n", cwd);
    char cmd[2048];
    strcpy(cmd, "../libs/bin/python3 ");
    strcat(cmd, "app.py");
    char output[SIZE_OUTPUT];
    printf("Running: %s\\n", cmd);
    FILE *fp = popen(cmd, "r");
    if (fp == NULL){
        fprintf(stderr, "could not run.\\n");
        return EXIT_FAILURE;
    }
    while(fgets(output, SIZE_OUTPUT, fp) != NULL) {
        printf("%s", output);
    }
    if (pclose(fp) != 0){
        fprintf(stderr, "could not run.\\n");
    }
    return EXIT_SUCCESS;
}