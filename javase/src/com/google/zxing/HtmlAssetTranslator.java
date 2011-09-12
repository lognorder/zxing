/*
 * Copyright 2011 ZXing authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.google.zxing;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.w3c.dom.bootstrap.DOMImplementationRegistry;
import org.w3c.dom.ls.DOMImplementationLS;
import org.w3c.dom.ls.LSSerializer;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import java.io.File;
import java.io.FilenameFilter;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedList;
import java.util.Queue;

/**
 * <p>A utility which auto-translates the English-language text in a directory of HTML documents using
 * Google Translate.</p>
 *
 * <p>Pass the Android client assets/ directory as first argument, and the language to translate to second.
 * Optionally, you can specify the files to translate individually.
 * Usage: {@code HtmlAssetTranslator android/assets/ es [file1.html file2.html ...]}</p>
 *
 * <p>This will translate all .html files in subdirectory html-en to directory html-es, for example.
 * Note that only text nodes in the HTML document are translated. Any text that is a child of a node
 * with {@code class="notranslate"} will not be translated. It will also add a note at the end of
 * the translated page that indicates it was automatically translated.</p>
 *
 * @author Sean Owen
 */
public final class HtmlAssetTranslator {

  private HtmlAssetTranslator() {}

  public static void main(String[] args) throws Exception {

    File assetsDir = new File(args[0]);
    File englishHtmlDir = new File(assetsDir, "html-en");
    String language = args[1];
    File targetHtmlDir = new File(assetsDir, "html-" + language);
    targetHtmlDir.mkdirs();

    final Collection<String> fileNamesToTranslate = new ArrayList<String>();
    for (int i = 2; i < args.length; i++) {
      fileNamesToTranslate.add(args[i]);
    }

    File[] sourceFiles = englishHtmlDir.listFiles(new FilenameFilter() {
      public boolean accept(File dir, String name) {
        return name.endsWith(".html") && (fileNamesToTranslate.isEmpty() || fileNamesToTranslate.contains(name));
      }
    });

    for (File sourceFile : sourceFiles) {

      File destFile = new File(targetHtmlDir, sourceFile.getName());

      DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
      DocumentBuilder builder = factory.newDocumentBuilder();
      Document document = builder.parse(sourceFile);

      Element rootElement = document.getDocumentElement();
      rootElement.normalize();

      Queue<Node> nodes = new LinkedList<Node>();
      nodes.add(rootElement);

      while (!nodes.isEmpty()) {
        Node node = nodes.poll();
        if (shouldTranslate(node)) {
          NodeList children = node.getChildNodes();
          for (int i = 0; i < children.getLength(); i++) {
            nodes.add(children.item(i));
          }
        }
        if (node.getNodeType() == Node.TEXT_NODE) {
          String text = node.getTextContent();
          if (text.trim().length() > 0) {
            text = StringsResourceTranslator.translateString(text, language);
            node.setTextContent(' ' + text + ' ');
          }
        }
      }

      String translationTextTranslated =
          StringsResourceTranslator.translateString("Translated by Google Translate.", language);
      Node translateText = document.createTextNode(translationTextTranslated);
      Node paragraph = document.createElement("p");
      paragraph.appendChild(translateText);
      Node body = rootElement.getElementsByTagName("body").item(0);
      body.appendChild(paragraph);

      DOMImplementationRegistry registry = DOMImplementationRegistry.newInstance();
      DOMImplementationLS impl = (DOMImplementationLS) registry.getDOMImplementation("LS");
      LSSerializer writer = impl.createLSSerializer();
      writer.writeToURI(document, destFile.toURI().toString());
    }
  }

  private static boolean shouldTranslate(Node node) {
    NamedNodeMap attributes = node.getAttributes();
    if (attributes == null) {
      return true;
    }
    Node classAttribute = attributes.getNamedItem("class");
    return classAttribute == null || !"notranslate".equals(classAttribute.getTextContent());
  }

}
