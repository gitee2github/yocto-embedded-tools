#include <stdio.h>
#include "openamp_module.h"

#define MCS_DEVICE_NAME    "/dev/mcs"
#define STR_TO_HEX         16
#define PAGE_SIZE          4096
#define PAGE_MASK          (~(PAGE_SIZE - 1))
#define PAGE_ALIGN(addr)   ((addr & PAGE_MASK) + PAGE_SIZE)

static int memfd;
static void *binaddr;
static int binsize;
void *shmaddr;

static int reserved_mem_init(void)
{
    int binfd;
    struct stat buf;
    void *file_addr;

    /* open memfd */
    memfd = open(MCS_DEVICE_NAME, O_RDWR | O_SYNC);
    if (memfd < 0) {
        printf("mcsmem open failed: %d\n", memfd);
        return -1;
    }

    /* open clientos bin file */
    binfd = open(target_binfile, O_RDONLY);
    if (binfd < 0) {
        printf("open %s failed, binfd:%d\n", target_binfile, binfd);
        return -1;
    }

    /* shared memory for virtio */
    shmaddr = mmap(NULL, VDEV_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, memfd, VDEV_START_ADDR);
    memset(shmaddr, 0, VDEV_SIZE);

    /* memory for loading clientos bin file */
    fstat(binfd, &buf);
    binsize = PAGE_ALIGN(buf.st_size);
    binaddr = mmap(NULL, binsize, PROT_READ | PROT_WRITE, MAP_SHARED, memfd, strtol(target_binaddr, NULL, STR_TO_HEX));
    memset(binaddr, 0, binsize);

    if (shmaddr < 0 || binaddr < 0) {
        printf("mmap reserved mem failed: shmaddr:%p, binaddr:%p\n", shmaddr, binaddr);
        return -1;
    }

    /* load clientos */
    file_addr = mmap(NULL, binsize, PROT_READ, MAP_PRIVATE, binfd, 0);
    memcpy(binaddr, file_addr, binsize);

    close(binfd);

    return 0;
}

static void reserved_mem_release(void)
{
    if (shmaddr)
        munmap(shmaddr, VDEV_SIZE);
    if (binaddr)
        munmap(binaddr, binsize);
    if (memfd)
        close(memfd);
}

int openamp_init(void)
{
    int ret;
    struct remoteproc *rproc;
    int cpu_state;

    /* secondary core power state must be CPU_STATE_OFF, avoid initialize repeatedly */
    cpu_state = acquire_cpu_state();
    if (cpu_state != CPU_STATE_OFF) {
        printf("cpu(%s) is already on(%d).\n", cpu_id, cpu_state);
        return -1;
    }

    ret = reserved_mem_init();
    if (ret) {
        printf("failed to init reserved mem\n");
        return ret;
    }

    rproc = create_remoteproc();
    if (!rproc) {
        printf("create remoteproc failed\n");
        return -1;
    }

    ret = remoteproc_start(rproc);
    if (ret) {
        printf("start processor failed\n");
        return ret;
    }

    virtio_init();
    rpmsg_module_init();

    return 0;
}

void openamp_deinit(void)
{
    printf("\nOpenAMP demo ended.\n");

    destory_remoteproc(); /* shutdown clientos first */
    virtio_deinit();
    reserved_mem_release();
}
