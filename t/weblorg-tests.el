;;; blorg-tests --- Static site generator for Emacs-Lisp; -*- lexical-binding: t -*-
;;
;; Author: Lincoln Clarete <lincoln@clarete.li>
;;
;; Copyright (C) 2020  Lincoln Clarete
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;;; Commentary:
;;
;;
;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'weblorg)


;; Test Helpers

(defmacro tests-fixture (path)
  "Expand the full PATH for a fixture."
  `(expand-file-name (format "t/fixtures/%s" ,path) default-directory))

(ert-deftest weblorg--bug29--post-url ()
  (weblorg-route
   :base-dir (tests-fixture "test1/")
   :name "my-route"
   :input-pattern "src/*.org"
   :template "my-post.html"
   :url "/{{ slug }}--{{ date | strftime(\"%Y-%m-%d\") }}.html")

  ;; When the collection and aggregation happen
  (let* ((route (weblorg--site-route (weblorg--site-get) "my-route"))
         (collection (weblorg--route-collect-and-aggregate route))
         (posts (mapcar #'cdar collection)))

    ;; Add template to be rendered; notice we still don't have the
    ;; `post.` variable because we're testing it without calling
    ;; aggregate.
    (templatel-env-add-template
     (gethash :template-env route)
     "my-post.html" (templatel-new "MY URL IS {{ url }}"))

    ;; We've only got one single post that's not a draft in that route
    (should (equal 1 (length posts)))

    ;; The post now gets the "post.route.name" name
    (should (equal "my-route" (weblorg--get-cdr
                               (weblorg--get-cdr (car posts) "route")
                               "name")))

    ;; Post is rendered with the URL link
    (should (equal "MY URL IS http://localhost:8000/a-simple-post--2020-09-05.html"
                   (weblorg--template-render route posts))))

  ;; reset the global to its initial state
  (clrhash weblorg--sites))

(ert-deftest weblorg--bug27-add-file-slug ()
  (should
            (equal
             (weblorg--get-cdr (weblorg--parse-org-file (tests-fixture "bug27/a_funny+file~name.with.many=chars.org"))
                               "file_slug")
             "a-funny-file-name-with-many-chars")))


(ert-deftest weblorg--bug26-export-org-with-right-include-path ()
  (should
            (equal
             (weblorg--get-cdr (weblorg--parse-org-file (tests-fixture "bug26/index.org"))
                               "html")
             "<p>
index
</p>

<p>
Included from file
</p>
")))

(ert-deftest weblorg--path ()
  (let ((route (weblorg-route
                :name "posts"
                :input-pattern "*.org"
                :template "post.html"
                :base-dir "/tmp/site"
                :url "/posts/{{ slug }}.html"
                :theme (lambda() "/tmp/theme"))))
    (should (equal
             '("/tmp/site/theme/template" "/tmp/theme/template")
             (weblorg--path route "template"))))
  (let ((route (weblorg-route
                :name "other-posts"
                :input-pattern "*.org"
                :template "post.html"
                :base-dir "/tmp/site"
                :url "/posts/{{ slug }}.html"
                :theme nil)))
    (should (equal
             '("/tmp/site/theme/template")
             (weblorg--path route "template"))))
  (clrhash weblorg--sites))

(ert-deftest weblorg--url-parse ()
  (should (equal
           '("doc" . (("slug" . "how-to-skydive")
                      ("section" . "breathing")))
           (weblorg--url-parse "doc,slug=how-to-skydive,section=breathing")))
  (should (equal
           '("blog-posts" . (("slug" . "moon-phases")))
           (weblorg--url-parse "blog-posts,slug=moon-phases"))))

(ert-deftest weblorg--url-for ()
  (let ((site (weblorg-site :base-url "https://example.com")))
    (weblorg-route
     :name "docs"
     :input-pattern "*.org"
     :input-exclude "index.org$"
     :template "post.html"
     :url "/documentation/{{ slug }}-{{ stuff }}.html"
     :site site)
    (should
     (equal
      "https://example.com/documentation/something-else.html"
      (weblorg--url-for-v "docs"
                        '(("slug" . "something")
                          ("stuff" . "else"))
                        site)))
    (clrhash weblorg--sites)))

(ert-deftest weblorg--slugify ()
  (should (equal (weblorg--slugify "!v0.1.1 - We've come a long way, friend!")
                 "v0-1-1-we-ve-come-a-long-way-friend")))

(ert-deftest weblorg--collect-n-aggr ()
  (weblorg-route
   :base-dir (tests-fixture "test1/")
   :name "route"
   :input-filter nil
   :input-pattern "src/*.org"
   :input-exclude "index.org$"
   :template "post.html"
   :url "/{{ slug }}.html")

  ;; When the collection and aggregation happen
  (let* ((route (weblorg--site-route (weblorg--site-get) "route"))
         (collection (weblorg--route-collect-and-aggregate route))
         (posts (mapcar #'cdar collection)))
    ;; we've got two posts there so far
    (should (equal (length collection) 2))

    ;; notice the list of files will be sorted
    (should (equal (mapcar (lambda(p) (weblorg--get-cdr p "slug")) posts)
                   (list "a-draft-post" "a-simple-post")))
    ;; also compare dates read and parsed from org files
    (should (equal (mapcar (lambda(p)
                             (format-time-string
                              "%Y-%m-%d"
                              (weblorg--get-cdr p "date")))
                           posts)
                   (list "2020-09-10" "2020-09-05"))))

  ;; reset the global to its initial state
  (clrhash weblorg--sites))

(ert-deftest weblorg--resolve-link ()
  ;; An implicit site gets created by this route that doesn't have a
  ;; site parameter
  (weblorg-route
   :name "docs"
   :input-pattern "*.org"
   :input-exclude "index.org$"
   :template "post.html"
   :url "/documentation/{{ slug }}-{{ stuff }}.html"
   :site (weblorg-site :base-url "https://example.com"))

  ;; When an URL for a given route is requested, then it should use
  ;; the `url' field of the route to interpolate the variables
  (should
   (equal (weblorg--url-for "docs,slug=overview,stuff=10" (weblorg-site :base-url "https://example.com"))
          "https://example.com/documentation/overview-10.html"))

  ;; Add anchor in any link it asked for
  (should
   (equal (weblorg--url-for "docs,slug=overview,stuff=10,anchor=sub-item" (weblorg-site :base-url "https://example.com"))
          "https://example.com/documentation/overview-10.html#sub-item"))

  ;; reset the global to its initial state
  (clrhash weblorg--sites))

;; Make sure we can register routes in a site and then retrieve them
;; later.
(ert-deftest weblorg--site-route--add-and-retrieve ()
  ;; An implicit site gets created by this route that doesn't have a
  ;; site parameter
  (weblorg-route
   :name "docs"
   :input-pattern ".*\\.org$"
   :input-exclude "index.org$"
   :template "post.html"
   :url "/{{ slug }}.html")

  ;; The site instance is being explicitly added to another site, so
  ;; this new route should not impact the previously defined one
  (weblorg-route
   :site (weblorg-site :base-url "https://example.com")
   :name "docs"
   :base-dir "/tmp/site"
   :theme "stuff"
   :input-pattern "docs/.*\\.org$"
   :input-exclude "index.org$"
   :template "docs.html"
   :url "docs/{{ slug }}.html")

  (let* ((site (weblorg--site-get))
         (route (weblorg--site-route site "docs")))
    (should (equal (gethash :name route) "docs"))
    (should (equal (gethash :input-pattern route) ".*\\.org$"))
    (should (equal (gethash :template route) "post.html"))
    (should (equal (gethash :url route) "/{{ slug }}.html"))
    (should (equal (gethash :input-exclude route) "index.org$")))

  (let* ((site (weblorg--site-get "https://example.com"))
         (route (weblorg--site-route site "docs")))
    (should (equal (gethash :name route) "docs"))
    (should (equal (gethash :input-pattern route) "docs/.*\\.org$"))
    (should (equal (gethash :template route) "docs.html"))
    (should (equal (gethash :url route) "docs/{{ slug }}.html"))
    (should (equal (gethash :input-exclude route) "index.org$"))
    (should (equal (gethash :theme route) "stuff")))

  ;; reset the global to its initial state
  (clrhash weblorg--sites))

;; Make sure that registering a new site works and that data
;; associated with it can be retrieved
(ert-deftest weblorg--site-get--success ()
  (weblorg-site :base-url "http://localhost:9000" :theme "stuff")
  (let ((the-same-weblorg (weblorg--site-get "http://localhost:9000")))
    (should (equal (gethash :base-url the-same-weblorg) "http://localhost:9000"))
    (should (equal (gethash :theme the-same-weblorg) "stuff")))
  ;; reset the global to its initial state
  (clrhash weblorg--sites))

;; Make sure this lil helper works
(ert-deftest weblorg--get--with-and-without-default ()
  (should (equal (weblorg--get '((:base-dir "expected")) :base-dir "wrong") "expected"))
  (should (equal (weblorg--get '() :base-dir "expected") "expected")))

;;; weblorg-tests.el ends here
