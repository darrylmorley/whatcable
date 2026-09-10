import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { feedPlugin } from "@11ty/eleventy-plugin-rss";
import syntaxHighlight from "@11ty/eleventy-plugin-syntaxhighlight";

export default async function (eleventyConfig) {
  eleventyConfig.addPlugin(syntaxHighlight);

  // Keep explorer markup, styles, code and data in sync across browser caches.
  eleventyConfig.addTransform("versionCableExplorer", function (content) {
    if (!this.page.outputPath?.endsWith("/inside-a-cable.html")) return content;
    const hash = createHash("sha256");
    for (const file of ["src/assets/cable-explorer/explorer.css", "src/assets/cable-explorer/explorer.js", "src/_data/explorer.json"]) {
      hash.update(readFileSync(file));
    }
    const version = hash.digest("hex").slice(0, 16);
    return content.replace(/(\/assets\/cable-explorer\/explorer\.(?:css|js))(?=["'])/g, `$1?v=${version}`);
  });


  eleventyConfig.addPlugin(feedPlugin, {
    type: "atom",
    outputPath: "/blog/feed.xml",
    collection: { name: "posts", limit: 20 },
    metadata: {
      language: "en",
      title: "WhatCable Blog",
      subtitle:
        "USB-C cables, Thunderbolt, and the deep weeds of port diagnostics.",
      base: "https://www.whatcable.uk/blog/",
      author: {
        name: "Darryl",
      },
    },
  });

  eleventyConfig.addFilter("stripDatePrefix", (slug) =>
    String(slug).replace(/^\d{4}-\d{2}-\d{2}-/, "")
  );

  eleventyConfig.addFilter("cleanUrl", (url) => {
    const u = String(url);
    if (u === "/") return "/";
    // Strip .html extension (posts now output as filename.html) then trailing slash.
    return u.replace(/\.html$/, "").replace(/\/$/, "");
  });

  // Treat "now", null, and undefined as today so templates can render
  // a build-time stamp without juggling Date objects in frontmatter.
  const resolveDate = (date) => {
    if (date == null || date === "now") return new Date();
    return new Date(date);
  };

  eleventyConfig.addFilter("isoDate", (date) => resolveDate(date).toISOString());

  eleventyConfig.addFilter("readableDate", (date) =>
    resolveDate(date).toLocaleDateString("en-GB", {
      year: "numeric",
      month: "long",
      day: "numeric",
    })
  );

  // Capture Eleventy's bundled markdown-it instance so we can render arbitrary
  // markdown strings (e.g. FAQ answers from a post's frontmatter) using the
  // same config as the post body.
  let mdLib = null;
  eleventyConfig.amendLibrary("md", (md) => {
    mdLib = md;
  });
  eleventyConfig.addFilter("markdownify", (str) => {
    if (!str) return "";
    return mdLib ? mdLib.render(String(str)) : String(str);
  });

  // Escape any </script> sequence inside a string that's about to be inlined
  // into a <script type="application/ld+json"> block. JSON itself doesn't
  // require this, but the browser's HTML parser will close the script tag
  // early if it sees the literal sequence anywhere in the content.
  eleventyConfig.addFilter("jsonLdSafe", (str) =>
    String(str || "").replace(/<\/(script)/gi, "<\\/$1")
  );

  eleventyConfig.addCollection("posts", (api) =>
    api
      .getFilteredByGlob("./src/blog/posts/**/*.md")
      .sort((a, b) => b.date - a.date)
  );

  // Wrap every <table> in a scrollable div so wide tables don't blow out the
  // layout on narrow screens. The markdown renderer can't add wrapper markup
  // directly, so this transform does it as a post-processing step on HTML.
  eleventyConfig.addTransform("wrapTables", function (content) {
    if (!this.page.outputPath?.endsWith(".html")) return content;
    return content
      .replace(/<table/g, '<div class="table-wrap"><table')
      .replace(/<\/table>/g, "</table></div>");
  });

  eleventyConfig.addTransform("stripFeedTrailingSlashes", function (content) {
    if (!this.page.outputPath || !this.page.outputPath.endsWith("feed.xml")) {
      return content;
    }
    return content
      .replace(/(https?:\/\/[^\s"<>]+?)\.html(?=["<\s])/g, "$1")
      .replace(/(https?:\/\/[^\s"<>]+?)\/(?=["<\s])/g, "$1");
  });

  eleventyConfig.addPassthroughCopy("src/assets/cable-explorer");
  eleventyConfig.addPassthroughCopy("src/assets/cable-database");
  eleventyConfig.addPassthroughCopy("src/icon.png");
  eleventyConfig.addPassthroughCopy("src/whatbattery-icon.png");
  eleventyConfig.addPassthroughCopy("src/whatport-icon.png");
  eleventyConfig.addPassthroughCopy("src/CNAME");
  eleventyConfig.addPassthroughCopy("src/robots.txt");
  eleventyConfig.addPassthroughCopy("src/screenshot*.webp");
  eleventyConfig.addPassthroughCopy("src/press");

  // Decap CMS lives at /admin. Copy it verbatim (no Nunjucks pass), so the
  // HTML/JS isn't accidentally parsed if it ever contains brace-heavy code.
  eleventyConfig.ignores.add("src/admin/**");
  eleventyConfig.addPassthroughCopy("src/admin");

  return {
    dir: {
      input: "src",
      output: "docs",
      includes: "_includes",
      layouts: "_layouts",
      data: "_data",
    },
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk",
  };
}
