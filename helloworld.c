#include <uefi.h>

/**
 * Classic Hello World example
 */
int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    printf("Hello World!\n");
    sleep(1);
    return 0;
}
