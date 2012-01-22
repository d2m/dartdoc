/**
 * Stores data to create navigation entries and search filters.
 * Serializes data into a dart file.
 */
class Search {
  /** Index of available documentation files. */
  List fileList;
  /** Inverted index, used in searchTerms. */
  List id;
  /** List of available navigation entries. */
  List<_NavItem> navigation;
  /** Searchindex. */
  Map<String, List> searchTerms;
  /** Names used for navigation icon entries. */
  List typ;
  
  Search()
  : fileList = [],
    id = [],
    navigation = [],
    searchTerms = {},
    typ = ['library', 'class', 'interface', 'exception'];
  
  /** Add a navigation entry. */
  void addNav(List a) {
    // lists are not hashable? this gets me poor performance
    _NavItem navitem = new _NavItem(a);
    if (navigation.length == 0) {
      navigation.add(navitem);
    } else {
      if (navigation.some((e) => e._hash == navitem._hash) != true) {
        navigation.add(navitem);
      }      
    }
  }
   
  /** Add/update a searchterm entry. */
  void addTerm(String a, List b) {
    _TermItem termitem = new _TermItem(b);
    // remove get/set
    a = a.toString().toLowerCase().split(':').last();
    // remove private entries
    if (a.startsWith('_') || termitem.filename.startsWith('_') || 
        termitem.filename.indexOf('/_') > -1) {
      return;
    }
    List key = [];
    if (searchTerms.containsKey(a)) {
      key = searchTerms[a];
    }
    key.add(termitem);
    searchTerms[a] = key;
  }

  /** Like [files.dart:endFile()], but write to current direcory. */
  void endLocalFile() {
    String outPath = _filePath;
    world.files.createDirectory(dirname(outPath), recursive: true);

    world.files.writeString(outPath, _file.toString());
    _filePath = null;
    _file = null;
  }
  
  /** 
   * Serialize a collection to a file. 
   * Works for String, int, List and Map.
   */
  void writeList(var l) {
    write('[');
    bool first = true;
    for (var item in l) {
      if (!first) write(', ');
      if (item is String) writeString(item);
      if (item is int) writeInt(item);
      if (item is List) writeList(item);
      if (item is Map) writeMap(item);
      first = false;
    }
    write(']');
  }

  /** Serializes a Map to a file. */
  void writeMap(Map m) {
    write('{');
    bool first = true;
    for (String key in m.getKeys()) {
      if (!first) writeln(',');
      writeString(key);
      write(': ');
      var value = m[key];
      if (value is String) writeString(value);
      if (value is int) writeInt(value);
      if (value is List) writeList(value);
      if (value is Map) writeMap(value);
      first = false;
    }
    write('}');
  }

  /** Serializes an int to a file. */
  void writeInt(int i) {
    write('$i');
  }

  /** Serializes a String to a file. */
  void writeString(String s) {
    // Escape enclosed quotes.
    s = s.replaceAll("'", "\\'");
    write("'$s'");
  }
  
  /** 
   * Write a dart file from a datastructure, create a sourceable file with 
   * contents of a Map ('./searching.dart').
   */
  void contents2dart(bool enableSearch) {
    var _out;
    // This file is used to be sourced into another dart file.
    startFile('searching.dart');

    // Enclosing function start.
    writeln('_terms() {');
        
    if (enableSearch == true) {

      // navigation is a list of (filename, typ, title, ...).
      // Create an inverted index for navigation.
      _out = [];

      for (_NavItem navitem in navigation) {
        if (fileList.indexOf(navitem.filename) == -1) {
          fileList.add(navitem.filename);
        }
        _out.add(fileList.indexOf(navitem.filename));
        _out.add(typ.indexOf(navitem.typ));
        _out.add(navitem.title);
      }
      navigation = _out;
      
      // searchTerms is a Map of (term, [filename, membername, ...]).
      // Create an inverted index.
      _out = {};
      for (String key in searchTerms.getKeys()) {
        List termitems = searchTerms[key];
        List bco = [];
        for (_TermItem termitem in termitems) {
          if (id.indexOf(termitem.memberid) == -1) {
            id.add(termitem.memberid);
          }
          bco.add(fileList.indexOf(termitem.filename));
          bco.add(id.indexOf(termitem.memberid));
        }
        _out[key] = bco;        
      }
      searchTerms = _out;
      
      // Result map holds data and indexes.
      Map out = {'nav': navigation,
                 'filelist': fileList,
                 'typ': typ,
                 'id': id,
                 'terms': searchTerms};

      // Write data.
      writeln('var terms = ');
      writeMap(out);
      writeln(';');
    } else {
      // Write data.
      writeln('var terms = null;');
    }
    
    // Enclosing function end.
    writeln('return terms;');
    writeln('}');

    // Close file.
    endLocalFile();
  } 
}

/** Helper class */
class _NavItem {
  String filename;
  String typ;
  String title;
  String _hash;
  
  _NavItem(a) {
    filename = a[0];
    typ = a[1];
    title = a[2];
    // poor man's hash for sorting.
    _hash = '$filename $typ $title';
  }
}

/** Helper class */
class _TermItem {
  String filename;
  String memberid;
  String _hash;
  
  _TermItem(a) {
    filename = a[0];
    memberid = a[1];
    // poor man's hash for sorting.
    _hash = '$filename $memberid';
  }
}