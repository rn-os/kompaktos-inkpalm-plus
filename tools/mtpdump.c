// mtpdump: recursively download an MTP folder (by name path) to a local dir.
// usage: mtpdump <remote/path e.g. Android/data> <local_dir>
#include <libmtp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>

static LIBMTP_mtpdevice_t *dev;
static long nfiles, nfail; static unsigned long long nbytes;

static void mkdirs(const char *p) {
  char tmp[4096]; snprintf(tmp, sizeof tmp, "%s", p);
  for (char *s = tmp + 1; *s; s++) if (*s == '/') { *s = 0; mkdir(tmp, 0755); *s = '/'; }
  mkdir(tmp, 0755);
}

static void walk(uint32_t storage, uint32_t parent, const char *local) {
  mkdirs(local);
  LIBMTP_file_t *f = LIBMTP_Get_Files_And_Folders(dev, storage, parent);
  while (f) {
    char path[4096]; snprintf(path, sizeof path, "%s/%s", local, f->filename);
    if (f->filetype == LIBMTP_FILETYPE_FOLDER) {
      walk(storage, f->item_id, path);
    } else if (LIBMTP_Get_File_To_File(dev, f->item_id, path, NULL, NULL) == 0) {
      nfiles++; nbytes += f->filesize;
      if (nfiles % 250 == 0) { printf("%ld files, %.1f MB\n", nfiles, nbytes / 1e6); fflush(stdout); }
    } else {
      nfail++; fprintf(stderr, "FAIL %s\n", path); LIBMTP_Clear_Errorstack(dev);
    }
    LIBMTP_file_t *n = f->next; LIBMTP_destroy_file_t(f); f = n;
  }
}

int main(int argc, char **argv) {
  if (argc != 3) { fprintf(stderr, "usage: %s remote/path local_dir\n", argv[0]); return 2; }
  LIBMTP_Init();
  LIBMTP_raw_device_t *raw; int nraw = 0;
  if (LIBMTP_Detect_Raw_Devices(&raw, &nraw) != 0 || nraw < 1) { fprintf(stderr, "no raw MTP device\n"); return 1; }
  dev = LIBMTP_Open_Raw_Device_Uncached(&raw[0]);
  if (!dev) { fprintf(stderr, "no MTP device\n"); return 1; }
  uint32_t storage = dev->storage->id, cur = LIBMTP_FILES_AND_FOLDERS_ROOT;
  char rp[1024]; snprintf(rp, sizeof rp, "%s", argv[1]);
  for (char *tok = strtok(rp, "/"); tok; tok = strtok(NULL, "/")) {
    LIBMTP_file_t *f = LIBMTP_Get_Files_And_Folders(dev, storage, cur), *hit = NULL;
    for (LIBMTP_file_t *x = f; x; x = x->next)
      if (x->filetype == LIBMTP_FILETYPE_FOLDER && !strcmp(x->filename, tok)) hit = x;
    if (!hit) { fprintf(stderr, "not found: %s\n", tok); return 1; }
    cur = hit->item_id;
    while (f) { LIBMTP_file_t *n = f->next; LIBMTP_destroy_file_t(f); f = n; }
  }
  walk(storage, cur, argv[2]);
  printf("DONE files=%ld bytes=%llu failed=%ld\n", nfiles, nbytes, nfail);
  LIBMTP_Release_Device(dev);
  return nfail ? 3 : 0;
}
