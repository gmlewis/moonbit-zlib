// This file is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/compress/zlib/writer.go
// which has the copyright notice:
// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

///|
// A Writer takes data written to it and writes the compressed
// form of that data to an underlying writer (see NewWriter).
struct Writer {
  mut w : &@io.Writer
  // level : Int // only support BestSpeed
  dict : Slice[Byte]
  mut compressor : @flate.Writer
  digest : &@hash.Hash32
  mut err : IOError?
  mut scratch : Slice[Byte] // [4]byte
  mut wrote_header : Bool
}

///|
// Writer::new creates a new Writer.
// Writes to the returned Writer are compressed and written to w.
//
// It is the caller's responsibility to call Close on the Writer when done.
// Writes may be buffered and not flushed until Close.
pub fn Writer::new(w : &@io.Writer) -> Writer {
  Writer::new_dict(w, Slice::new([]))
}

///|
// Writer::new_dict is like Writer::new but specifies a dictionary to compress with.
pub fn Writer::new_dict(w : &@io.Writer, dict : Slice[Byte]) -> Writer {
  {
    w,
    dict,
    compressor: @flate.Writer::new_dict(w, dict),
    digest: @adler32.new(),
    err: None,
    scratch: Slice::new([0, 0, 0, 0]),
    wrote_header: false,
  }
}

///|
// reset clears the state of the Writer z such that it is equivalent to its
// initial state from NewWriterLevel or NewWriterLevelDict, but instead writing
// to w.
pub fn Writer::reset(self : Writer, w : &@io.Writer) -> Unit {
  self.w = w
  // self.level and self.dict left unchanged.
  self.compressor = @flate.Writer::new_dict(w, self.dict)
  self.digest.reset()
  self.err = None
  self.scratch = Slice::new([0, 0, 0, 0])
  self.wrote_header = false
}

///|
// write_header writes the ZLIB header.
fn Writer::write_header(self : Writer) -> IOError? {
  self.wrote_header = true
  // ZLIB has a two-byte header (as documented in RFC 1950).
  // The first four bits is the CINFO (compression info), which is 7 for the default deflate window size.
  // The next four bits is the CM (compression method), which is 8 for deflate.
  self.scratch[0] = 0x78
  // The next two bits is the FLEVEL (compression level). The four values are:
  // 0=fastest, 1=fast, 2=default, 3=best.
  // The next bit, FDICT, is set if a dictionary is given.
  // The final five FCHECK bits form a mod-31 checksum.
  // This package only supports BestSpeed:
  self.scratch[1] = 0
  if self.dict.length() > 0 {
    self.scratch[1] = self.scratch[1] | (b'\x01' << 5)
  }
  self.scratch[1] += (31U - be_uint16(self.scratch[:2]) % 31).to_byte()
  let (_, err) = self.w.write(self.scratch[0:2])
  if err != None {
    return err
  }
  if self.dict.length() > 0 {
    // The next four bytes are the Adler-32 checksum of the dictionary.
    be_put_uint32(self.scratch, @adler32.checksum(self.dict))
    let (_, err) = self.w.write(self.scratch[0:4])
    if err != None {
      return err
    }
  }
  // if self.compressor == nil {
  // 	// Initialize deflater unless the Writer is being reused
  // 	// after a reset call.
  // 	self.compressor, err = flate.NewWriterDict(self.w, self.level, self.dict)
  // 	if err != nil {
  // 		return err
  // 	}
  // 	self.digest = adler32.New()
  // }
  None
}

///|
fn be_put_uint32(b : Slice[Byte], value : UInt) -> Unit {
  b[3] = (value & 0xff).to_byte()
  b[2] = ((value >> 8) & 0xff).to_byte()
  b[1] = ((value >> 16) & 0xff).to_byte()
  b[0] = ((value >> 24) & 0xff).to_byte()
}

///|
/// write writes a compressed form of p to the underlying io.Writer. The
/// compressed bytes are not necessarily flushed until the Writer is closed or
/// explicitly flushed.
pub impl @io.Writer for Writer with write(self, p) {
  if not(self.wrote_header) {
    self.err = self.write_header()
  }
  if self.err != None {
    return (0, self.err)
  }
  if p.length() == 0 {
    return (0, None)
  }
  let (n, err) = self.compressor.write(p)
  if err != None {
    self.err = err
    return (n, self.err)
  }
  let _ = self.digest.write(p)
  return (n, self.err)
}

///|
// flush flushes the Writer to its underlying io.Writer.
pub fn Writer::flush(self : Writer) -> IOError? {
  if not(self.wrote_header) {
    self.err = self.write_header()
  }
  // if self.err != None {
  // 	return self.err
  // }
  // self.err = self.compressor.flush()
  return self.err
}

///|
// close closes the Writer, flushing any unwritten data to the underlying
// io.Writer, but does not close the underlying io.Writer.
pub impl @io.Closer for Writer with close(self) {
  if not(self.wrote_header) {
    self.err = self.write_header()
  }
  if self.err != None {
    return self.err
  }
  self.err = self.compressor.close()
  if self.err != None {
    return self.err
  }
  let checksum = self.digest.sum32()
  // ZLIB (RFC 1950) is big-endian, unlike GZIP (RFC 1952).
  be_put_uint32(self.scratch, checksum)
  let (_, err) = self.w.write(self.scratch)
  self.err = err
  self.err
}
