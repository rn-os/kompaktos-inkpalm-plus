/* Stub libheif for the stock Android 11 libskia on a GSI: libskia only imports
 * createHeifDecoder(); returning NULL makes SkHeifCodec report HEIF as unsupported,
 * which avoids pulling the whole Android 11 libmedia/audio stack into vendor processes. */
void *_Z17createHeifDecoderv(void) { return 0; }
