// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Functions for working with files and paths.

/** The path to the file currently being written to, relative to [outdir]. */
String _filePath;

/** The file currently being written to. */
StringBuffer _file;

/** Path to generate HTML files into. */
final _outdir = 'docs';

startFile(String path) {
  _filePath = path;
  _file = new StringBuffer();
}

write(String s) {
  _file.add(s);
}

writeln(String s) {
  write(s);
  write('\n');
}

endFile() {
  String outPath = '$_outdir/$_filePath';
  world.files.createDirectory(dirname(outPath), recursive: true);

  world.files.writeString(outPath, _file.toString());
  _filePath = null;
  _file = null;
}

/**
 * Converts [fullPath] which is understood to be a full path from the root of
 * the generated docs to one relative to the current file.
 */
String relativePath(String fullPath) {
  // Don't make it relative if it's an absolute path.
  if (isAbsolute(fullPath)) return fullPath;

  // TODO(rnystrom): Walks all the way up to root each time. Shouldn't do this
  // if the paths overlap.
  return repeat('../', countOccurrences(_filePath, '/')) + fullPath;
}

/** Gets whether or not the given URL is absolute or relative. */
bool isAbsolute(String url) {
  // TODO(rnystrom): This is a bit hackish. We consider any URL that lacks
  // a scheme to be relative.
  return const RegExp(@'^\w+:').hasMatch(url);
}

/** Gets the URL to the documentation for [library]. */
libraryUrl(Library library) => '${sanitize(library.name)}.html';

/** Gets the URL for the documentation for [type]. */
typeUrl(Type type) {
  if (type.isTop) return '${sanitize(type.library.name)}.html';
  // Always get the generic type to strip off any type parameters or arguments.
  // If the type isn't generic, genericType returns `this`, so it works for
  // non-generic types too.
  return '${sanitize(type.library.name)}/${type.genericType.name}.html';
}

/** Gets the URL for the documentation for [member]. */
memberUrl(Member member) {
  final typeUrl = typeUrl(member.declaringType);
  if (!member.isConstructor) return '$typeUrl#${member.name}';
  if (member.constructorName == '') return '$typeUrl#new:${member.name}';
  return '$typeUrl#new:${member.name}.${member.constructorName}';
}

/** Gets the anchor id for the document for [member]. */
memberAnchor(Member member) => '${member.name}';
