/** Helper class */
class NavItem {
  String filename;
  String typ;
  String title;
  String _hash;
  
  NavItem(a) {
    filename = a[0];
    typ = a[1];
    title = a[2];
    _hash = '$filename $typ $title';
  }
    
}

/** Helper class */
class TermItem {
  String filename;
  String memberid;
  String _hash;
  
  TermItem(a) {
    filename = a[0];
    memberid = a[1];
    _hash = '$filename $memberid';
  }
  
}

/**
 * Stores data to create navigation entries and search filters.
 * Serializes data into a dart file.
 */
class Search {
  /** Index of available documentation files. */
  List filelist;
  /** Inverted index, used in searchterms. */
  List id;
  /** List of available navigation entries. */
  List<NavItem> navigation;
  /** Searchindex. */
  Map<String, List> searchterms;
  /** Names used for navigation icon entries. */
  List typ;
  
  Search()
  : filelist = [],
    id = [],
    navigation = [],
    searchterms = {},
    typ = ['library', 'class', 'interface', 'exception'];
  
  /** Add a navigation entry. */
  void addNav(List a) {
    // lists are not hashable? this gets me poor performance
    NavItem b = new NavItem(a);
    if (navigation.length == 0) {
      navigation.add(b);
    } else {
      if (navigation.some((e) => e._hash == b._hash) != true) {
        navigation.add(b);
      }      
    }
  }
   
  /** Add/update a searchterm entry. */
  void addTerm(String a, List b) {
    TermItem termitem = new TermItem(b);
    // remove get/set
    a = a.toString().toLowerCase().split(':').last();
    // remove private entries
    if (a.startsWith('_') || termitem.filename.startsWith('_') || 
        termitem.filename.indexOf('/_') > -1) {
      return;
    }
    List key = [];
    if (searchterms.containsKey(a)) {
      key = searchterms[a];
    }
    key.add(termitem);
    searchterms[a] = key;
  }

  /** Like [files/endFile], but write to current direcory. */
  void endLocalFile() {
    String outPath = _filePath;
    world.files.createDirectory(dirname(outPath), recursive: true);

    world.files.writeString(outPath, _file.toString());
    _filePath = null;
    _file = null;
  }
  
  /** 
   * Serialize a collection to a file. 
   * Works for String, int and List.
   */
  void writelist(var l) {
    write('[');
    bool first = true;
    for (var item in l) {
      if (!first) write(', ');
      if (item is String) {
        // escape quotes
        item = item.replaceAll("'", "\\'");
        write("'$item'");
      }
      if (item is int) write(item);
      if (item is List) writelist(item);
      first = false;
    }
    write(']');
  }

  
  /** 
   * Write a dart file from a datastructure, create a sourceable file with 
   * contents of a Map ('./searching.dart').
   */
  void contents2dart(bool enableSearch) {
    var _out;
    startFile('searching.dart');
    // this file is used to be sourced into another dart file.
    writeln('_terms() {');
    
    if (enableSearch == true) {
      writeln('var terms = {};');
      
      // create an inverted index for navigation
      _out = [];
      for (NavItem i in navigation) {
        if (filelist.indexOf(i.filename) == -1) {
          filelist.add(i.filename);
        }
        _out.add(filelist.indexOf(i.filename));
        _out.add(typ.indexOf(i.typ));
        _out.add(i.title);
      }
      navigation = _out;
      
      // searchterms is a Map of (term, [[filename, membername], ...])
      // create an inverted index
      _out = {};
      for (String key in searchterms.getKeys()) {
        List termitems = searchterms[key];
        List bco = [];
        for (TermItem termitem in termitems) {
          if (id.indexOf(termitem.memberid) == -1) {
            id.add(termitem.memberid);
          }
          bco.add(filelist.indexOf(termitem.filename));
          bco.add(id.indexOf(termitem.memberid));
        }
        _out[key] = bco;        
      }
      searchterms = _out;
      
      // write file entires.
      write("terms['nav'] = ");
      writelist(navigation);
      writeln(';');
      write("terms['filelist'] = ");
      writelist(filelist);
      writeln(';');
      write("terms['typ'] = ");
      writelist(typ);
      writeln(';');
      write("terms['id'] = ");
      writelist(id);
      writeln(';');
      
      writeln("terms['terms'] = {");
      var v, first;
      first = true;
      for (String key in searchterms.getKeys()) {
        if (!first) writeln(', ');
        write("'$key': ");
        v = searchterms[key];
        writelist(v);
        first = false;
      }
      writeln('};');
    } else {
      writeln('var terms = null;');
    }
    
    writeln('return terms;');
    writeln('}');

    endLocalFile();
  } 

}
