///|
/// This file is based on the Go implementation found here:
/// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/compress/zlib/reader.go
/// which has the copyright notice:
/// Copyright 2009 The Go Authors. All rights reserved.
/// Use of this source code is governed by a BSD-style
/// license that can be found in the LICENSE file.
///
/// Package zlib implements reading and writing of zlib format compressed data,
/// as specified in RFC 1950.
///
/// The implementation provides filters that uncompress during reading
/// and compress during writing.  For example, to write compressed data
/// to a buffer:
///
/// 	var b bytes.Buffer
/// 	w := zlib.NewWriter(&b)
/// 	w.Write(Slice[Byte]("hello, world\n"))
/// 	w.close()
///
/// and to read that data back:
///
/// 	r, err := zlib.Reader::new(&b)
/// 	io.Copy(os.Stdout, r)
/// 	r.close()
const ZLIB_DEFLATE = b'\x08'

///|
const ZLIB_MAX_WINDOW = b'\x07'

///|
typealias @io.Slice

///|
typealias @io.IOError

///|
/// err_checksum is returned when reading ZLIB data that has an invalid checksum.
pub let err_checksum : IOError = IOError("zlib: invalid checksum")

///|
/// err_dictionary is returned when reading ZLIB data that has an invalid dictionary.
pub let err_dictionary : IOError = IOError("zlib: invalid dictionary")

///|
/// err_header is returned when reading ZLIB data that has an invalid header.
pub let err_header : IOError = IOError("zlib: invalid header")

///|
struct Reader {
  mut r : &@flate.Reader
  mut decompressor : &@io.ReadCloser
  mut digest : &@hash.Hash32
  mut err : IOError?
  mut scratch : Slice[Byte] // [4]byte
}

///|
/// Resetter resets a ReadCloser returned by [Reader::new] or [Reader::new_dict]
/// to switch to a new underlying Reader. This permits reusing a ReadCloser
/// instead of allocating a new one.
pub(open) trait Resetter {
  /// reset discards any buffered data and resets the Resetter as if it was
  /// newly initialized with the given reader.
  reset(Self, &@flate.Reader, Slice[Byte]) -> IOError?
}

///|
/// Reader::new creates a new ReadCloser.
/// Reads from the returned ReadCloser read and decompress data from r.
/// If r does not implement [io.ByteReader], the decompressor may read more
/// data than necessary from r.
/// It is the caller's responsibility to call close on the ReadCloser when done.
///
/// The [io.ReadCloser] returned by Reader::new also implements [Resetter].
pub fn Reader::new(r : &@flate.Reader) -> (&@io.ReadCloser, IOError?) {
  Reader::new_dict(r, Slice::new([]))
}

///|
/// Reader::new_dict is like [Reader::new] but uses a preset dictionary.
/// Reader::new_dict ignores the dictionary if the compressed data does not refer to it.
/// If the compressed data refers to a different dictionary, Reader::new_dict returns [err_dictionary].
///
/// The ReadCloser returned by Reader::new_dict also implements [Resetter].
pub fn Reader::new_dict(
  r : &@flate.Reader,
  dict : Slice[Byte]
) -> (&@io.ReadCloser, IOError?) {
  let z : Reader = {
    r,
    decompressor: &@flate.Reader::new(r),
    digest: @adler32.new(),
    err: None,
    scratch: Slice::new([0, 0, 0, 0]),
  }
  let err = z.reset(r, dict)
  (z, err)
}

///|
pub impl @io.Reader for Reader with read(self, p) {
  if self.err != None {
    return (0, self.err)
  }
  let (n, err) = self.decompressor.read(p)
  self.err = err
  guard self.digest.write(p[0:n]) is (_, None)
  if self.err != Some(@io.eof) {
    // In the normal case we return here.
    return (n, self.err)
  }

  // Finished file; check checksum.
  let (_, err) = @io.read_full(self.r, self.scratch)
  if err != None {
    let mut err = err
    if err == Some(@io.eof) {
      err = Some(@io.err_unexpected_eof)
    }
    self.err = err
    return (n, self.err)
  }
  // ZLIB (RFC 1950) is big-endian, unlike GZIP (RFC 1952).
  let checksum = be_uint32(self.scratch)
  if checksum != self.digest.sum32() {
    self.err = Some(err_checksum)
    return (n, self.err)
  }
  (n, Some(@io.eof))
}

///|
fn be_uint16(b : Slice[Byte]) -> UInt {
  (b[0].to_uint() << 8) | b[1].to_uint()
}

///|
fn be_uint32(b : Slice[Byte]) -> UInt {
  (b[0].to_uint() << 24) |
  (b[1].to_uint() << 16) |
  (b[2].to_uint() << 8) |
  b[3].to_uint()
}

///|
/// Calling close does not close the wrapped [io.Reader] originally passed to [Reader::new].
/// In order for the ZLIB checksum to be verified, the reader must be
/// fully consumed until the [io.eof].
pub impl @io.Closer for Reader with close(self) {
  if self.err != None && self.err != Some(@io.eof) {
    return self.err
  }
  self.err = self.decompressor.close()
  self.err
}

///|
pub impl Resetter for Reader with reset(self, r, dict) {
  self.r = r
  self.digest = @adler32.new()
  self.err = None
  self.scratch = Slice::new([0, 0, 0, 0])
  // if fr, ok := r.(flate.Reader); ok {
  // 	self.r = fr
  // } else {
  // 	self.r = bufio.Reader::new(r)
  // }

  // Read the header (RFC 1950 section 2.2.).
  let (_, err) = @io.read_full(self.r, self.scratch[0:2])
  self.err = err
  if self.err != None {
    if self.err == Some(@io.eof) {
      self.err = Some(@io.err_unexpected_eof)
    }
    return self.err
  }
  let h = be_uint16(self.scratch[:2])
  if (self.scratch[0] & 0x0f) != ZLIB_DEFLATE ||
    self.scratch[0] >> 4 > ZLIB_MAX_WINDOW ||
    h % 31 != 0 {
    self.err = Some(err_header)
    return self.err
  }
  let have_dict = (self.scratch[1] & 0x20) != 0
  if have_dict {
    let (_, err) = @io.read_full(self.r, self.scratch)
    self.err = err
    if self.err != None {
      if self.err == Some(@io.eof) {
        self.err = Some(@io.err_unexpected_eof)
      }
      return self.err
    }
    let checksum = be_uint32(self.scratch)
    if checksum != @adler32.checksum(dict) {
      self.err = Some(err_dictionary)
      return self.err
    }
  }

  //
  // if self.decompressor == None {
  if have_dict {
    self.decompressor = &@flate.Reader::new_dict(self.r, dict)
  } else {
    self.decompressor = &@flate.Reader::new(self.r)
  }
  // } else {
  // 	self.decompressor.(flate.Resetter).reset(self.r, dict)
  // }
  None
}
