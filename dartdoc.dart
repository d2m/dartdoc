// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * To use it, from this directory, run:
 *
 *     $ ./dartdoc <path to .dart file>
 *
 * This will create a "docs" directory with the docs for your libraries. To
 * create these beautiful docs, dartdoc parses your library and every library
 * it imports (recursively). From each library, it parses all classes and
 * members, finds the associated doc comments and builds crosslinked docs from
 * them.
 */
#library('dartdoc');

#import('dart:json');
#import('../../frog/lang.dart');
#import('../../frog/file_system.dart');
#import('../../frog/file_system_node.dart');
#import('../../frog/lib/node/node.dart');
#import('classify.dart');
#import('markdown.dart', prefix: 'md');

#source('comment_map.dart');
#source('files.dart');
#source('utils.dart');
#source('search.dart');

/**
 * Generates completely static HTML containing everything you need to browse
 * the docs. The only client side behavior is trivial stuff like syntax
 * highlighting code.
 */
final MODE_STATIC = 0;

/**
 * Generated docs do not include baked HTML navigation. Instead, a single
 * `nav.json` file is created and the appropriate navigation is generated
 * client-side by parsing that and building HTML.
 *
 * This dramatically reduces the generated size of the HTML since a large
 * fraction of each static page is just redundant navigation links.
 *
 * In this mode, the browser will do a XHR for nav.json which means that to
 * preview docs locally, you will need to enable requesting file:// links in
 * your browser or run a little local server like `python -m SimpleHTTPServer`.
 */
final MODE_LIVE_NAV = 1;

/**
 * Run this from the `utils/dartdoc` directory.
 */
void main() {
  // The entrypoint of the library to generate docs for.
  final entrypoint = process.argv[process.argv.length - 1];
  
  // Parse the dartdoc options.
  bool includeSource = true;
  bool enableSearch = true;
  var mode = MODE_LIVE_NAV;

  for (int i = 2; i < process.argv.length - 1; i++) {
    final arg = process.argv[i];
    switch (arg) {
      case '--no-code':
        includeSource = false;
        break;
        
      case '--no-search':
        enableSearch = false;
        break;

      case '--mode=static':
        mode = MODE_STATIC;
        break;

      case '--mode=live-nav':
        mode = MODE_LIVE_NAV;
        break;

      default:
        print('Unknown option: $arg');
    }
  }

  final files = new NodeFileSystem();
  parseOptions('../../frog', [] /* args */, files);
  initializeWorld(files);

  var dartdoc;
  final elapsed = time(() {
    dartdoc = new Dartdoc();
    dartdoc.includeSource = includeSource;
    dartdoc.enableSearch = enableSearch;
    dartdoc.mode = mode;

    dartdoc.document(entrypoint);
  });

  print('Documented ${dartdoc._totalLibraries} libraries, ' +
      '${dartdoc._totalTypes} types, and ' +
      '${dartdoc._totalMembers} members in ${elapsed}msec.');
}

class Dartdoc {
  /** Set to `false` to not include the source code in the generated docs. */
  bool includeSource = true;
  /** Set to `false` to not include the search widget in the generated docs. */
  bool enableSearch = true;

  /**
   * Dartdoc can generate docs in a few different ways based on how dynamic you
   * want the client-side behavior to be. The value for this should be one of
   * the `MODE_` constants.
   */
  int mode = MODE_LIVE_NAV;

  /**
   * The title used for the overall generated output. Set this to change it.
   */
  String mainTitle = 'Dart Documentation';

  /**
   * The URL that the Dart logo links to. Defaults "index.html", the main
   * page for the generated docs, but can be anything.
   */
  String mainUrl = 'index.html';

  /** Set this to add footer text to each generated page. */
  String footerText = '';

  CommentMap _comments;

  /** The library that we're currently generating docs for. */
  Library _currentLibrary;

  /** The type that we're currently generating docs for. */
  Type _currentType;

  /** The member that we're currently generating docs for. */
  Member _currentMember;
  
  /** Search backend */
  Search search;

  int _totalLibraries = 0;
  int _totalTypes = 0;
  int _totalMembers = 0;

  Dartdoc()
    : _comments = new CommentMap(),
      search = new Search() {
    // Patch in support for [:...:]-style code to the markdown parser.
    // TODO(rnystrom): Markdown already has syntax for this. Phase this out?
    md.InlineParser.syntaxes.insertRange(0, 1,
        new md.CodeSyntax(@'\[\:((?:.|\n)*?)\:\]'));

    md.setImplicitLinkResolver((name) => resolveNameReference(name,
            library: _currentLibrary, type: _currentType,
            member: _currentMember));
  }

  document(String entrypoint) {
    var oldDietParse = options.dietParse;
    try {
      options.dietParse = true;

      // Handle the built-in entrypoints.
      switch (entrypoint) {
        case 'corelib':
          world.getOrAddLibrary('dart:core');
          world.getOrAddLibrary('dart:coreimpl');
          world.getOrAddLibrary('dart:json');
          world.process();
          break;

        case 'dom':
          world.getOrAddLibrary('dart:core');
          world.getOrAddLibrary('dart:coreimpl');
          world.getOrAddLibrary('dart:json');
          world.getOrAddLibrary('dart:dom');
          world.process();
          break;

        case 'html':
          world.getOrAddLibrary('dart:core');
          world.getOrAddLibrary('dart:coreimpl');
          world.getOrAddLibrary('dart:json');
          world.getOrAddLibrary('dart:dom');
          world.getOrAddLibrary('dart:html');
          world.process();
          break;

        default:
          // Normal entrypoint script.
          world.processDartScript(entrypoint);
      }

      world.resolveAll();

      // Generate the docs.
      //if (mode == MODE_LIVE_NAV) docNavigationJson();
      if (mode == MODE_LIVE_NAV) docNavigationDart();
      if (enableSearch) docSearchNavigation();

      docIndex();
      for (final library in world.libraries.getValues()) {
        docLibrary(library);
      }
      // Write dart source file.
      search.contents2dart(enableSearch);
    } finally {
      options.dietParse = oldDietParse;
    }
  }

  /**
   * Writes the page header with the given [title] and [breadcrumbs]. The
   * breadcrumbs are an interleaved list of links and titles. If a link is null,
   * then no link will be generated. For example, given:
   *
   *     ['foo', 'foo.html', 'bar', null]
   *
   * It will output:
   *
   *     <a href="foo.html">foo</a> &rsaquo; bar
   */
  writeHeader(String title, List<String> breadcrumbs) {
    write(
        '''
        <!DOCTYPE html>
        <html>
        <head>
        ''');
    writeHeadContents(title);

    // Add data attributes describing what the page documents.
    var data = '';
    if (_currentLibrary != null) {
      data += ' data-library="${md.escapeHtml(_currentLibrary.name)}"';
    }

    if (_currentType != null) {
      data += ' data-type="${md.escapeHtml(typeName(_currentType))}"';
    }
    // [data-path] is used to compute the urls in the search navigation. 
    data += ' data-path="' + relativePath('.') + '"';
    write(
        '''
        </head>
        <body$data>
        <div class="page">
        <div class="header">
          ${a(mainUrl, '<div class="logo"></div>')}
          ${a('index.html', mainTitle)}
        ''');

    // Write the breadcrumb trail.
    for (int i = 0; i < breadcrumbs.length; i += 2) {
      if (breadcrumbs[i + 1] == null) {
        write(' &rsaquo; ${breadcrumbs[i]}');
      } else {
        write(' &rsaquo; ${a(breadcrumbs[i + 1], breadcrumbs[i])}');
      }
    }
    writeln('</div>');

    docNavigation();
    writeln('<div class="content">');
  }

  String get clientScript() {
    switch (mode) {
      case MODE_STATIC:   return 'client-static';
      case MODE_LIVE_NAV: return 'client-live-nav';
      default: throw 'Unknown mode $mode.';
    }
  }

  writeHeadContents(String title) {
    writeln(
        '''
        <meta charset="utf-8">
        <title>$title</title>
        <link rel="stylesheet" type="text/css"
          href="${relativePath('styles.css')}" />
          <link rel="stylesheet" type="text/css" media="print"
            href="${relativePath('print.css')}" />
        <link href="http://fonts.googleapis.com/css?family=Open+Sans:400,600,700,800" rel="stylesheet" type="text/css">
        <link rel="shortcut icon" href="${relativePath('favicon.ico')}" />
        <script src="${relativePath('$clientScript.js')}"></script>
        ''');
  }

  writeFooter() {
    writeln(
        '''
        </div>
        <div class="clear"></div>
        </div>
        <div class="footer">$footerText</div>
        </body></html>
        ''');
  }

  docIndex() {
    startFile('index.html');

    writeHeader(mainTitle, []);

    writeln('<h2>$mainTitle</h2>');
    writeln('<h3>Libraries</h3>');

    for (final library in orderByName(world.libraries)) {
      writeln(
          '''
          <h4>${a(libraryUrl(library), library.name)}</h4>
          ''');
    }

    writeFooter();
    endFile();
  }

  /**
   * Walks the libraries and creates a JSON object containing the data needed
   * to generate navigation for them.
   */
  docNavigationJson() {
    startFile('nav.json');

    final libraries = {};

    for (final library in orderByName(world.libraries)) {
      final types = [];

      for (final type in orderByName(library.types)) {
        if (type.isTop) continue;
        if (type.name.startsWith('_')) continue;

        final kind = type.isClass ? 'class' : 'interface';
        final url = typeUrl(type);
        types.add({ 'name': typeName(type), 'kind': kind, 'url': url });
      }

      libraries[library.name] = types;
    }

    writeln(JSON.stringify(libraries));
    endFile();
  }

  docNavigationDart() {
    startFile('navigating.dart');

    final libraries = {};

    for (final library in orderByName(world.libraries)) {
      final types = [];

      for (final type in orderByName(library.types)) {
        if (type.isTop) continue;
        if (type.name.startsWith('_')) continue;

        final kind = type.isClass ? 'class' : 'interface';
        final url = typeUrl(type);
        types.add({ 'name': typeName(type), 'kind': kind, 'url': url });
      }

      libraries[library.name] = types;
    }

    // Enclosing function start.
    writeln('_libraries() {');
    writeln('var libraries = ');
    search.writeMap(libraries);
    writeln(';');
    // Enclosing function end.
    writeln('return libraries;');
    writeln('}');

    // Write to the current directory.
    search.endLocalFile();
  }

  docNavigation() {
    if (mode == MODE_STATIC) {
      writeln(
        '''
        <div class="nav built">
        ''');

      var map = {};
      for (var library in orderByName(world.libraries)) {
        map[library.name] = library;
      }
      
      for (final library in orderByName(map)) {
        write('<h2><div class="icon-library"></div>');

        if ((_currentLibrary == library) && (_currentType == null)) {
          write('<strong>${library.name}</strong>');
        } else {
          write('${a(libraryUrl(library), library.name)}');
        }
        write('</h2>');

        // Only expand classes in navigation for current library.
        if (_currentLibrary == library) docLibraryNavigation(library);
      }
    } else {
      writeln(
        '''
        <div class="nav">
        ''');

    }
    writeln('</div>');
  }

  /** Writes the navigation for the types contained by the given library. */
  docLibraryNavigation(Library library) {
    // Show the exception types separately.
    final types = <Type>[];
    final exceptions = <Type>[];
    
    for (final type in orderByName(library.types)) {
      if (type.isTop) continue;
      if (type.name.startsWith('_')) continue;

      if (type.name.endsWith('Exception')) {
        exceptions.add(type);
      } else {
        types.add(type);
      }
    }

    if ((types.length == 0) && (exceptions.length == 0)) return;

    writeType(String icon, Type type) {
      write('<li>');
      if (_currentType == type) {
        write(
            '<div class="icon-$icon"></div><strong>${typeName(type)}</strong>');
      } else {
        write(a(typeUrl(type),
            '<div class="icon-$icon"></div>${typeName(type)}'));
      }
      writeln('</li>');
    }

    writeln('<ul>');
    types.forEach((type) => writeType(type.isClass ? 'class' : 'interface',
        type));
    exceptions.forEach((type) => writeType('exception', type));
    writeln('</ul>');
  }

  /** Stores the navigation for the types contained by the given library. */
  docSearchNavigation() {
    assert(enableSearch == true);
    
    var map = {};
    for (var library in orderByName(world.libraries)) {
      map[library.name] = library;
    }
    
    for (final library in orderByName(map)) {
      
      // Show the exception types separately.
      final types = <Type>[];
      final exceptions = <Type>[];
      
      // Add search navigation entry for libraries
      search.addNav([libraryUrl(library), 'library', library.name]);      
  
      for (final type in orderByName(library.types)) {
        if (type.isTop) continue;
        if (type.name.startsWith('_')) continue;
  
        if (type.name.endsWith('Exception')) {
          exceptions.add(type);
        } else {
          types.add(type);
        }
      }
  
      if ((types.length == 0) && (exceptions.length == 0)) return;
  
      writeType(String icon, Type type) {
        search.addNav([typeUrl(type), icon, typeName(type)]);        
      }
  
      types.forEach((type) => writeType(type.isClass ? 'class' : 'interface',
          type));
      exceptions.forEach((type) => writeType('exception', type));
    }
  }

  docLibrary(Library library) {
    _totalLibraries++;
    _currentLibrary = library;
    _currentType = null;

    startFile(libraryUrl(library));
    writeHeader(library.name, [library.name, libraryUrl(library)]);
    writeln('<h2>Library <strong>${library.name}</strong></h2>');

    // Look for a comment for the entire library.
    final comment = _comments.findLibrary(library.baseSource);
    if (comment != null) {
      final html = md.markdownToHtml(comment);
      writeln('<div class="doc">$html</div>');
    }

    // Document the top-level members.
    docMembers(library.topType);

    // Document the types.
    final classes = <Type>[];
    final interfaces = <Type>[];
    final exceptions = <Type>[];

    for (final type in orderByName(library.types)) {
      if (type.isTop) continue;
      if (type.name.startsWith('_')) continue;

      if (type.name.endsWith('Exception')) {
        exceptions.add(type);
      } else if (type.isClass) {
        classes.add(type);
      } else {
        interfaces.add(type);
      }
    }

    docTypes(classes, 'Classes');
    docTypes(interfaces, 'Interfaces');
    docTypes(exceptions, 'Exceptions');

    writeFooter();
    endFile();

    for (final type in library.types.getValues()) {
      if (!type.isTop) docType(type);
    }
  }

  docTypes(List<Type> types, String header) {
    if (types.length == 0) return;

    writeln('<div>');
    writeln('<h3>$header</h3>');

    for (final type in types) {
      writeln(
          '''
          <div class="type">
          <h4>
            ${a(typeUrl(type), "<strong>${typeName(type)}</strong>")}
          </h4>
          </div>
          ''');
    }
    writeln('</div>');
  }

  docType(Type type) {
    _totalTypes++;
    _currentType = type;

    startFile(typeUrl(type));

    final typeTitle =
      '${type.isClass ? "Class" : "Interface"} ${typeName(type)}';
    writeHeader('Library ${type.library.name} / $typeTitle',
        [type.library.name, libraryUrl(type.library),
         typeName(type), typeUrl(type)]);
    writeln(
        '''
        <h2>${type.isClass ? "Class" : "Interface"}
            <strong>${typeName(type, showBounds: true)}</strong></h2>
        ''');

    docInheritance(type);

    docCode(type.span, getTypeComment(type));
    docConstructors(type);
    docMembers(type);

    writeFooter();
    endFile();
  }

  /** Document the superclass, superinterfaces and default class of [Type]. */
  docInheritance(Type type) {
    final isSubclass = (type.parent != null) && !type.parent.isObject;

    Type defaultType;
    if (type.definition is TypeDefinition) {
      TypeDefinition definition = type.definition;
      if (definition.defaultType != null) {
        defaultType = definition.defaultType.type;
      }
    }

    if (isSubclass ||
        (type.interfaces != null && type.interfaces.length > 0) ||
        (defaultType != null)) {
      writeln('<p>');

      if (isSubclass) {
        write('Extends ${typeReference(type.parent)}. ');
      }

      if (type.interfaces != null && type.interfaces.length > 0) {
        var interfaceStr = joinWithCommas(map(type.interfaces, typeReference));
        write('Implements ${interfaceStr}. ');
      }

      if (defaultType != null) {
        write('Has default class ${typeReference(defaultType)}.');
      }
    }
  }

  /** Document the constructors for [Type], if any. */
  docConstructors(Type type) {
    final names = type.constructors.getKeys().filter(
      (name) => !name.startsWith('_'));

    if (names.length > 0) {
      writeln('<div>');
      writeln('<h3>Constructors</h3>');
      names.sort((x, y) => x.toUpperCase().compareTo(y.toUpperCase()));

      for (final name in names) {
        docMethod(type, type.constructors[name], constructorName: name);
      }
      writeln('</div>');
    }
  }

  void docMembers(Type type) {
    // Collect the different kinds of members.
    final staticMethods = [];
    final staticFields = [];
    final instanceMethods = [];
    final instanceFields = [];

    for (final member in orderByName(type.members)) {
      if (member.name.startsWith('_')) continue;

      final methods = member.isStatic ? staticMethods : instanceMethods;
      final fields = member.isStatic ? staticFields : instanceFields;

      if (member.isProperty) {
        if (member.canGet) methods.add(member.getter);
        if (member.canSet) methods.add(member.setter);
      } else if (member.isMethod) {
        methods.add(member);
      } else if (member.isField) {
        fields.add(member);
      }
    }

    if (staticMethods.length > 0) {
      final title = type.isTop ? 'Functions' : 'Static Methods';
      writeln('<div>');
      writeln('<h3>$title</h3>');
      for (final method in staticMethods) docMethod(type, method);
      writeln('</div>');
    }

    if (staticFields.length > 0) {
      final title = type.isTop ? 'Variables' : 'Static Fields';
      writeln('<div>');
      writeln('<h3>$title</h3>');
      for (final field in staticFields) docField(type, field);
      writeln('</div>');
    }

    if (instanceMethods.length > 0) {
      writeln('<div>');
      writeln('<h3>Methods</h3>');
      for (final method in instanceMethods) docMethod(type, method);
      writeln('</div>');
    }

    if (instanceFields.length > 0) {
      writeln('<div>');
      writeln('<h3>Fields</h3>');
      for (final field in instanceFields) docField(type, field);
      writeln('</div>');
    }
  }

  /**
   * Documents the [method] in type [type]. Handles all kinds of methods
   * including getters, setters, and constructors.
   */
  docMethod(Type type, MethodMember method, [String constructorName = null]) {
    _totalMembers++;
    _currentMember = method;

    writeln('<div class="method"><h4 id="${memberAnchor(method)}">');

    if (includeSource) {
      writeln('<span class="show-code">Code</span>');
    }

    if (method.isConstructor) {
      write(method.isConst ? 'const ' : 'new ');
    }

    if (constructorName == null) {
      annotateType(type, method.returnType);
    }

    // Translate specially-named methods: getters, setters, operators.
    var name = method.name;
    if (name.startsWith('get:')) {
      // Getter.
      name = 'get ${name.substring(4)}';
    } else if (name.startsWith('set:')) {
      // Setter.
      name = 'set ${name.substring(4)}';
    } else if (name == ':negate') {
      // Dart uses 'negate' for prefix negate operators, not '!'.
      name = 'operator negate';
    } else {
      // See if it's an operator.
      name = TokenKind.rawOperatorFromMethod(name);
      if (name == null) {
        name = method.name;
      } else {
        name = 'operator $name';
      }
    }

    write('<strong>$name</strong>');

    // Named constructors.
    if (constructorName != null && constructorName != '') {
      write('.');
      write(constructorName);
    }

    docParamList(type, method);
    
    // Add serch term entries.
    if (enableSearch == true) {
      if (typeName(type) == null) {
        search.addTerm(memberAnchor(method), [libraryUrl(type.library), 
                                              memberAnchor(method)]);
      } else {
        search.addTerm(memberAnchor(method), [typeUrl(type), 
                                              memberAnchor(method)]);
      }
    }

    write(''' <a class="anchor-link" href="#${memberAnchor(method)}"
              title="Permalink to ${typeName(type)}.$name">#</a>''');
    writeln('</h4>');

    docCode(method.span, getMethodComment(method), showCode: true);

    writeln('</div>');
  }

  /** Documents the field [field] of type [type]. */
  docField(Type type, FieldMember field) {
    _totalMembers++;
    _currentMember = field;

    writeln('<div class="field"><h4 id="${memberAnchor(field)}">');

    if (includeSource) {
      writeln('<span class="show-code">Code</span>');
    }

    if (field.isFinal) {
      write('final ');
    } else if (field.type.name == 'Dynamic') {
      write('var ');
    }

    annotateType(type, field.type);
    
    // Add serch term entries.
    if (enableSearch == true) {
      if (typeName(type) == null) {
        search.addTerm(memberAnchor(field), [libraryUrl(type.library), 
                                              memberAnchor(field)]);
      } else {
        search.addTerm(memberAnchor(field), [typeUrl(type), 
                                              memberAnchor(field)]);
      }
    }

    write(
        '''
        <strong>${field.name}</strong> <a class="anchor-link"
            href="#${memberAnchor(field)}"
            title="Permalink to ${typeName(type)}.${field.name}">#</a>
        </h4>
        ''');

    docCode(field.span, getFieldComment(field), showCode: true);
    writeln('</div>');
  }

  docParamList(Type enclosingType, MethodMember member) {
    write('(');
    bool first = true;
    bool inOptionals = false;
    for (final parameter in member.parameters) {
      if (!first) write(', ');

      if (!inOptionals && parameter.isOptional) {
        write('[');
        inOptionals = true;
      }

      annotateType(enclosingType, parameter.type, parameter.name);

      // Show the default value for named optional parameters.
      if (parameter.isOptional && parameter.hasDefaultValue) {
        write(' = ');
        // TODO(rnystrom): Using the definition text here is a bit cheap.
        // We really should be pretty-printing the AST so that if you have:
        //   foo([arg = 1 + /* comment */ 2])
        // the docs should just show:
        //   foo([arg = 1 + 2])
        // For now, we'll assume you don't do that.
        write(parameter.definition.value.span.text);
      }

      first = false;
    }

    if (inOptionals) write(']');
    write(')');
  }

  /**
   * Documents the code contained within [span] with [comment]. If [showCode]
   * is `true` (and [includeSource] is set), also includes the source code.
   */
  docCode(SourceSpan span, String comment, [bool showCode = false]) {
    writeln('<div class="doc">');
    if (comment != null) {
      writeln(md.markdownToHtml(comment));
    }

    if (includeSource && showCode) {
      writeln('<pre class="source">');
      writeln(md.escapeHtml(unindentCode(span)));
      writeln('</pre>');
    }

    writeln('</div>');
  }

  /** Get the doc comment associated with the given type. */
  String getTypeComment(Type type) => _comments.find(type.span);

  /** Get the doc comment associated with the given method. */
  String getMethodComment(MethodMember method) => _comments.find(method.span);

  /** Get the doc comment associated with the given field. */
  String getFieldComment(FieldMember field) => _comments.find(field.span);

  /**
   * Creates a hyperlink. Handles turning the [href] into an appropriate
   * relative path from the current file.
   */
  String a(String href, String contents, [String css]) {
    final cssClass = css == null ? '' : ' class="$css"';
    return '<a href="${relativePath(href)}"$cssClass>$contents</a>';
  }

  /**
   * Writes a type annotation for the given type and (optional) parameter name.
   */
  annotateType(Type enclosingType, Type type, [String paramName = null]) {
    // Don't bother explicitly displaying Dynamic.
    if (type.isVar) {
      if (paramName !== null) write(paramName);
      return;
    }

    // For parameters, handle non-typedefed function types.
    if (paramName !== null) {
      final call = type.getCallMethod();
      if (call != null) {
        annotateType(enclosingType, call.returnType);
        write(paramName);

        docParamList(enclosingType, call);
        return;
      }
    }

    linkToType(enclosingType, type);

    write(' ');
    if (paramName !== null) write(paramName);
  }

  /** Writes a link to a human-friendly string representation for a type. */
  linkToType(Type enclosingType, Type type) {
    if (type is ParameterType) {
      // If we're using a type parameter within the body of a generic class then
      // just link back up to the class.
      write(a(typeUrl(enclosingType), type.name));
      return;
    }

    // Link to the type.
    // Use .genericType to avoid writing the <...> here.
    write(a(typeUrl(type), type.genericType.name));

    // See if it's a generic type.
    if (type.isGeneric) {
      // TODO(rnystrom): This relies on a weird corner case of frog. Currently,
      // the only time we get into this case is when we have a "raw" generic
      // that's been instantiated with Dynamic for all type arguments. It's kind
      // of strange that frog works that way, but we take advantage of it to
      // show raw types without any type arguments.
      return;
    }

    // See if it's an instantiation of a generic type.
    final typeArgs = type.typeArgsInOrder;
    if (typeArgs != null) {
      write('&lt;');
      bool first = true;
      for (final arg in typeArgs) {
        if (!first) write(', ');
        first = false;
        linkToType(enclosingType, arg);
      }
      write('&gt;');
    }
  }

  /** Creates a linked cross reference to [type]. */
  typeReference(Type type) {
    // TODO(rnystrom): Do we need to handle ParameterTypes here like
    // annotation() does?
    return a(typeUrl(type), typeName(type), css: 'crossref');
  }

  /** Generates a human-friendly string representation for a type. */
  typeName(Type type, [bool showBounds = false]) {
    // See if it's a generic type.
    if (type.isGeneric) {
      final typeParams = [];
      for (final typeParam in type.genericType.typeParameters) {
        if (showBounds &&
            (typeParam.extendsType != null) &&
            !typeParam.extendsType.isObject) {
          final bound = typeName(typeParam.extendsType, showBounds: true);
          typeParams.add('${typeParam.name} extends $bound');
        } else {
          typeParams.add(typeParam.name);
        }
      }

      final params = Strings.join(typeParams, ', ');
      return '${type.name}&lt;$params&gt;';
    }

    // See if it's an instantiation of a generic type.
    final typeArgs = type.typeArgsInOrder;
    if (typeArgs != null) {
      final args = Strings.join(map(typeArgs, (arg) => typeName(arg)), ', ');
      return '${type.genericType.name}&lt;$args&gt;';
    }

    // Regular type.
    return type.name;
  }

  /**
   * Remove leading indentation to line up with first line.
   */
  unindentCode(SourceSpan span) {
    final column = getSpanColumn(span);
    final lines = span.text.split('\n');
    // TODO(rnystrom): Dirty hack.
    for (final i = 1; i < lines.length; i++) {
      lines[i] = unindent(lines[i], column);
    }

    final code = Strings.join(lines, '\n');
    return code;
  }

  /**
   * This will be called whenever a doc comment hits a `[name]` in square
   * brackets. It will try to figure out what the name refers to and link or
   * style it appropriately.
   */
  md.Node resolveNameReference(String name, [Member member = null,
      Type type = null, Library library = null]) {
    makeLink(String href) {
      final anchor = new md.Element.text('a', name);
      anchor.attributes['href'] = relativePath(href);
      anchor.attributes['class'] = 'crossref';
      return anchor;
    }

    findMember(Type type, String memberName) {
      final member = type.members[memberName];
      if (member == null) return null;

      // Special case: if the member we've resolved is a property (i.e. it wraps
      // a getter and/or setter then *that* member itself won't be on the docs,
      // just the getter or setter will be. So pick one of those to link to.
      if (member.isProperty) {
        return member.canGet ? member.getter : member.setter;
      }

      return member;
    }

    // See if it's a parameter of the current method.
    if (member != null) {
      for (final parameter in member.parameters) {
        if (parameter.name == name) {
          final element = new md.Element.text('span', name);
          element.attributes['class'] = 'param';
          return element;
        }
      }
    }

    // See if it's another member of the current type.
    if (type != null) {
      final member = findMember(type, name);
      if (member != null) {
        return makeLink(memberUrl(member));
      }
    }

    // See if it's another type or a member of another type in the current
    // library.
    if (library != null) {
      // See if it's a constructor
      final constructorLink = (() {
        final match = new RegExp(@'new (\w+)(?:\.(\w+))?').firstMatch(name);
        if (match == null) return;
        final type = library.types[match[1]];
        if (type == null) return;
        final constructor = type.getConstructor(
            match[2] == null ? '' : match[2]);
        if (constructor == null) return;
        return makeLink(memberUrl(constructor));
      })();
      if (constructorLink != null) return constructorLink;

      // See if it's a member of another type
      final foreignMemberLink = (() {
        final match = new RegExp(@'(\w+)\.(\w+)').firstMatch(name);
        if (match == null) return;
        final type = library.types[match[1]];
        if (type == null) return;
        final member = findMember(type, match[2]);
        if (member == null) return;
        return makeLink(memberUrl(member));
      })();
      if (foreignMemberLink != null) return foreignMemberLink;

      final type = library.types[name];
      if (type != null) {
        return makeLink(typeUrl(type));
      }

      // See if it's a top-level member in the current library.
      final member = findMember(library.topType, name);
      if (member != null) {
        return makeLink(memberUrl(member));
      }
    }

    // TODO(rnystrom): Should also consider:
    // * Names imported by libraries this library imports.
    // * Type parameters of the enclosing type.

    return new md.Element.text('code', name);
  }

  // TODO(rnystrom): Move into SourceSpan?
  int getSpanColumn(SourceSpan span) {
    final line = span.file.getLine(span.start);
    return span.file.getColumn(line, span.start);
  }
}
