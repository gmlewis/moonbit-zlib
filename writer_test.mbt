// This file is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/compress/zlib/writer_test.go
// which has the copyright notice:
// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

///|
typealias Slice[T] = @io.Slice[T]

// let filenames = []string{
// 	"../testdata/gettysburg.txt",
// 	"../testdata/e.txt",
// 	"../testdata/pi.txt",
// }

///|
let data = [b"test a reasonable sized string that can be compressed"]

// // Tests that compressing and then decompressing the given file at the given compression level and dictionary
// // yields equivalent bytes to the original file.
// fn test_file_level_dict(name: String, lev: SliceeBint], d string) {
// 	// Read the file, as golden output.
// 	golden, err := os.Open(fn)
// 	if err != nil {
// 		raise TestError("%s (level=%d, dict=%q): %v", fn, level, d, err)
// 		return
// 	}
// 	defer golden.Close()
// 	b0, err0 := io.read_all(golden)
// 	if err0 != nil {
// 		raise TestError("%s (level=%d, dict=%q): %v", fn, level, d, err0)
// 		return
// 	}
// 	test_dict(t, fn, b0, level, d)
// }

///|
fn dump(b : Slice[Byte]) -> String {
  b
  .to_bytes()
  .to_array()
  .map(fn(b) { b.to_int() })
  .to_string()
  .replace_all(old=",", new="")
}

///|
fn test_dict(name : String, b0 : Slice[Byte], d : Bytes) -> Unit!TestError {
  // Make dictionary, if given.
  let mut dict = Slice::new([])
  if d.length() > 0 {
    dict = Slice::new(d.to_array())
  }
  let pipew = @io.Buffer::new()
  let zlibw = @zlib.Writer::new_dict(pipew, dict)
  let (_, err) = zlibw.write(b0)
  if err != None {
    raise TestError("\{name} (dict=\{dump(dict)}): \{err}")
  }
  guard let None = zlibw.close()

  //
  let (zlibr, err) = @zlib.Reader::new_dict(pipew, dict)
  if err != None {
    raise TestError("\{name} (dict=\{dump(dict)}): \{err}")
  }
  guard let None = zlibr.close()

  // Compare the decompressed data.
  let (b1, err1) = @io.read_all(zlibr)
  if err1 != None {
    raise TestError("\{name} (dict=\{dump(dict)}): \{err1}")
  }
  if b0.length() != b1.length() {
    raise TestError(
      "\{name} (dict=\{dump(dict)}): length mismatch \{b0.length()} versus \{b1.length()}",
    )
  }
  for i = 0; i < b0.length(); i = i + 1 {
    if b0[i] != b1[i] {
      raise TestError(
        "\{name} (dict=\{dump(dict)}): mismatch at \{i}, \{b0[i].to_int()} versus \{b1[i].to_int()}\n",
      )
    }
  }
}

test "writer" {
  for i, s in data {
    let b = Slice::new(s.to_array())
    let tag = "#\{i+1}"
    test_dict!(tag, b, b"")
  }
}
