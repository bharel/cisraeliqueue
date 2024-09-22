# Configuration file for the Sphinx documentation builder.
#
# For the full list of built-in configuration values, see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Project information -----------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#project-information

project = 'cisraeliqueue'
copyright = '2024, Bar Harel'
author = 'Bar Harel'
release = '0.0.1a'

# -- General configuration ---------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#general-configuration

extensions = [
    "sphinx.ext.intersphinx",
    "sphinx.ext.extlinks"
]

intersphinx_mapping = {'python': ('http://docs.python.org/3/', None), }

templates_path = ['_templates']
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']

SOURCE_URI = (
    "https://github.com/bharel/cisraeliqueue/tree/master/israeliqueue/%s")

extlinks = {
    "source": (SOURCE_URI, "%s"),
}

extlinks_detect_hardcoded_links = True

# -- Options for HTML output -------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#options-for-html-output

html_theme = 'python_docs_theme'
html_static_path = ['_static']

html_favicon = "_static/favicon.ico"

html_theme_options = {
    "root_icon": "favicon.ico",
    "root_include_title": False,
    "root_name": "cIsraeliQueue documentation",
    "root_url": "index.html"
}
