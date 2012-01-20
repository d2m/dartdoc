var terms;
var path;
var timeouthandle;

searchWidget() {
  terms = _terms();
  if (terms != null) {
    addSearchWidget();
  }
}

buildsearchnav() {
  if (timeouthandle != null) {
    window.clearTimeout(timeouthandle);
  }
  var checked = document.query('input#qc');
  var search = document.query('input#q');
  var content = document.query('.content');
  var listing = make_listing(search, checked);
  var directory = document.query('.nav');
  var dirlist = dir_list(listing, search, checked);
  directory.nodes.clear();
  directory.nodes.add(dirlist);
  content_filter(listing, search, checked, content);      
} 

waitfornavbuilt() {
  var dir = document.query('.nav');
  if (!dir.classes.contains('built')) {
    timeouthandle = window.setTimeout(waitfornavbuilt, 20);
  } else {
    buildsearchnav();
  }
}

addSearchWidget() {
  path = document.query('body').attributes['data-path'];
  print('Search is enabled');
  var nav = document.query('.header');
  var content = document.query('.content');
  var directory = document.query('.nav');
  var query = widget();
  nav.nodes.add(query);
  var submit = document.query('input#qb');
  var checked = document.query('input#qc');
  var search = document.query('input#q');
  if (document.cookie != '') {
    var c = document.cookie.split(';');
    for (var cv in c) {
      cv = cv.trim();
      var ca = cv.split('=');
      if (ca[0] == 'dartdocs-search') {
        search.value = ca[1];
      }
      if (ca[0] == 'dartdocs-exact') {
        checked.checked = (ca[1] == 'true' ? true : false);
      }
    }
  } else {
    var qs = window.location.search;
    if (qs != '' && qs[0] == '?') {
      qs = qs.substring(1);
      var qa = qs.split('&');
      for (var qi in qa) {
        var qis = qi.split('=');
        if (qis[0] == 'q') {
          search.value = qis[1];
        }
        if (qis[0] == 'e') {
          if (qis[1] == 'true') {
            checked.checked = true;
          } else {
            checked.checked = false;
          };
        }
      }
    }
  }
  var qs = window.location.search;
  if (qs != '') {
    waitfornavbuilt();
  }
  submit.on.click.add((e){
    document.cookie = 'dartdocs-search=${search.value}; path=/; ';
    document.cookie = 'dartdocs-exact=${checked.checked}; path=/; ';
    if (search.value.trim() != '') {
      var q = '?q=${search.value}&e=${checked.checked}';
      window.location.href = '$path/index.html$q';
    }
  });
  search.on.keyUp.add((e) {
    if (e.keyCode == 13) {
      submit.click();
    }
  });
  checked.on.click.add((e) {
    if (search.value != '') {
      submit.click();
    }
  });
}

widget() {
  return new Element.html(
    '''
    <div style="float:right; display:inline;padding-right:22px;">
    <input id="q"> &nbsp; &nbsp; exact <input type="checkbox" id="qc"> &nbsp; 
    <input type="button" id="qb" value="Search">
    <style>.hidden {display: none;}
    .matching li {
      font: 600 13px/22px 'Open Sans', 'Lucida Sans Unicode', 'Lucida Grande', sans-serif;
      list-style-type: none;
      white-space: nowrap;
    }
    </style></div>
    '''
    );
}

tuple(l) {
  var out = [];
  var n = l.length;
  for (var i = 0; i < n; i = i + 2) {
    out.add([l[i], l[i+1]]);
  }
  return out;
}

triple(l) {
  var out = [];
  var n = l.length;
  for (var i = 0; i < n; i = i + 3) {
    out.add([l[i], l[i+1], l[i+2]]);
  }
  return out;
}

make_listing(search, checked) {
  search = search.value.toLowerCase();
  var k = terms['terms'].getKeys();
  var out = [];
  add_terms(item) {
    item[0] = terms['filelist'][item[0]];
    item[1] = terms['id'][item[1]];
    out.add(item);
  }
  if (checked.checked == true) {
    if (terms['terms'].containsKey(search)) {
      tuple(terms['terms'][search]).forEach(add_terms);
    }
  } else {
    get_terms(key) {
      if (new RegExp(search).hasMatch(key)) {
        tuple(terms['terms'][key]).forEach(add_terms);
      }
    }
    k.forEach(get_terms);    
  }        
  return out;
}

dir_list(listing, search, checked) {
  var nav = triple(terms['nav']);
  var l = {};
  for (var li in listing) {
    l[li[0]] = '';
  }
  var out = '';
  var startul = false;
  var endul = false;
  for (var li in nav) {
    var li0 = terms['filelist'][li[0]];
    var li1 = terms['typ'][li[1]];
    var startuls = '';
    var enduls = '';    
    var contained = l.containsKey(li0);
    var isLib = (li1 == 'library');
    var q = '';
    if (search.value != '') {
      q = '?q=${search.value}&e=${checked.checked}';
    }
    if ( isLib || contained) {
      if (isLib && contained) {
        if (endul == true) {
          enduls = '</ul>';
        }
        out += '$enduls<h2><div class="icon-library"></div><a href="$path/${li0}$q">${li[2]}</a></h2>';
        startul = true;
        endul = false;
      }
      if (isLib && !contained) {
        if (endul == true) {
          enduls = '</ul>';
        }
        out += '$enduls<h2><div class="icon-library"></div>${li[2]}</h2>';
        startul = true;
        endul = false;
      }
      if (!isLib && contained) {
        if (startul == true) {
          startuls = '<ul>';
        }
        out += '$startuls<li><div class="icon-${li1}"></div><a href="$path/${li0}$q">${li[2]}</a></li>';
        startul = false;
        endul = true;
      }
    }
  }
  if (endul == true) {
    out += '</ul>';
  }
  return new Element.html('<div>$out</div>');
}

content_filter(listing, search, checked, c) {
  var h2 = c.query('h2');
  var query = search.value.trim();
  if (checked.checked == false) {
    query = '*$query*';
  }
  var h2t = h2.innerHTML;
  h2.innerHTML = 'Results for <strong>${_escape(query)}</strong> in $h2t';
  var mh4 = c.queryAll('.method h4');
  var fh4 = c.queryAll('.field h4');
  var th4 = c.queryAll('.type h4');
  var href = window.location.href;
  var match = [];
  for (var l in listing) {
    if (href.indexOf(l[0]) > -1) {
      match.add(l[1]);
    }
  }
  for (var m in mh4) {
    if (match.indexOf(m.attributes['id']) == -1 ) {
      m.parent.classes.add('hidden');
    }
  }
  for (var f in fh4) {
    if (match.indexOf(f.attributes['id']) == -1 ) {
      f.parent.classes.add('hidden');
    }
  }
  for (var t in th4) {
    t.parent.classes.add('hidden');
  }
  if (window.location.href.indexOf('/index.html') > -1) {
    var h3 = c.queryAll('h3');
    var h4 = c.queryAll('h4');
    for (var i in h3) {
      i.classes.add('hidden');
    }
    for (var i in h4) {
      i.classes.add('hidden');
    }
    c.nodes.add(dir_stats(listing));
    c.nodes.add(types_list(search, checked));
  }
  var h3s = c.queryAll('h3');
  for (var h3 in h3s) {
    var p = h3.parent;
    var h = p.queryAll('.hidden');
    var m = p.queryAll('.method');
    var f = p.queryAll('.field');
    var t = p.queryAll('.type');
    if (h.length == (m.length + f.length + t.length)) {
      p.classes.add('hidden');
    }
  }
  return '';
}

/** Escape HTML special chars. */
String _escape(String str) {
  str = str.replaceAll('&','&amp;');
  str = str.replaceAll('<','&lt;');
  str = str.replaceAll('>','&gt;');
  str = str.replaceAll('"','&quot;');
  str = str.replaceAll("'",'&#x27;');
  str = str.replaceAll('/','&#x2F;');
  return str;
}

dir_stats(listing) {
  var stats = {'lib': 0, 'type': 0, 'member': listing.length};
  var nav = triple(terms['nav']);
  var l = {};
  var llib = {};
  for (var li in listing) {
    l[li[0]] = '';
    llib[li[0].split('/')[0].replaceAll('.html', '')] = '';
  }
  stats['lib'] = llib.getKeys().length;
  var out = new Element.tag('div');
  for (var li in nav) {
    var li0 = terms['filelist'][li[0]];
    var li1 = terms['typ'][li[1]];
    var contained = l.containsKey(li0);
    var isLib = (li1 == 'library');
    if ( isLib || contained) {
      if (!isLib && contained) {
        stats['type'] += 1;
      }
    }
  }
  var members = (stats['member'] == 1) ? 'member' : 'members';
  var libraries = (stats['lib'] == 1) ? 'library' : 'libraries';
  var types = (stats['type'] == 1) ? 'type' : 'types';
  out.nodes.add(new Element.html('<h4>Found ${stats['member']} $members in ' +
    '${stats['lib']} $libraries and ${stats['type']} $types.</h4>'));
  return out;
}

types_list(search, checked) {
  var l = [];
  var s = search.value.toLowerCase().trim();
  var nav = triple(terms['nav']);
  if (checked.checked == true) {
    for (var i in nav) {
      if (i[2].toLowerCase() == s) {
        var i0 = terms['filelist'][i[0]];
        var i1 = terms['typ'][i[1]];
        l.add([i0, i1, i[2]]);
      }
    }
  } else {
    for (var i in nav) {
      if (i[2].toLowerCase().indexOf(s) > -1) {
        var i0 = terms['filelist'][i[0]];
        var i1 = terms['typ'][i[1]];
        l.add([i0, i1, i[2]]);
      }
    }    
  }
  var out = new Element.tag('div');
  out.classes.add('matching');
  if (l.length > 0) {
    out.nodes.add(new Element.tag('p'));
    out.nodes.add(new Element.html('<h4>Search term also matching these library/type names:</h4>'));
    var list = new Element.tag('ul');
    for (var i in l) {
      var e = new Element.html('<li><div class="icon-${i[1]}"></div><a href="$path/${i[0]}">${i[2]}</a></li>');
      list.nodes.add(e);
    }
    out.nodes.add(list);
  }
  return out;
}
