;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(in-package :nyxt)

(defvar *inspected-values* (tg:make-weak-hash-table :test 'equal))

(export-always 'sequence-p)
(defun sequence-p (object)
  "Return true if OBJECT is a sequence that's not a string."
  (typep object '(and sequence (not string))))

(export-always 'scalar-p)
(defun scalar-p (object)
  ;; REVIEW: List direct T subclasses instead?
  "Return true if OBJECT is of one of the following types:
- symbol,
- character,
- string,
- non-complex number."
  (funcall (alex:disjoin
            'symbolp
            'characterp
            'stringp
            (alex:rcurry 'typep '(and number (not complex))))
           object))

(export-always 'inspected-value)
(defmethod inspected-value (id)
  (gethash id *inspected-values*))

(defmethod (setf inspected-value) (new-value id)
  (setf (gethash id *inspected-values*) new-value))

(defun link-to (object)
  (let ((id (get-unique-identifier *browser*)))
    (if (scalar-p object)
        (spinneret:with-html-string
          (:raw (escaped-literal-print object)))
        (progn
          (setf (inspected-value id) object)
          (spinneret:with-html-string
            (:a :href (nyxt-url 'describe-value :id id)
                (:raw (escaped-literal-print object))))))))

(defun escaped-literal-print (value)
  (spinneret:with-html-string
    (:code (:raw (spinneret::escape-string (format nil "~s" value))))))

(export-always 'value->html)
(defgeneric value->html (value &optional nested-p)
  (:method :around (value &optional nested-p)
    (let ((spinneret:*html-style* :tree)
          (*print-case* :downcase))
      (call-next-method value nested-p)))
  (:method (value &optional nested-p)
    (declare (ignore nested-p))
    (escaped-literal-print value))
  (:method ((value null) &optional nested-p)
    (declare (ignore nested-p))
    (escaped-literal-print value))
  (:method ((value string) &optional nested-p)
    (declare (ignore nested-p))
    (escaped-literal-print value))
  (:documentation "Produce HTML showing the structure of the VALUE.
If it's NESTED-P, compress the output.

Redefine this method if you want to have a different markup for Lisp values in
help buffers, REPL and elsewhere."))

(defmethod value->html ((value list) &optional nested-p)
  (spinneret:with-html-string
    (cond
      ((trivial-types:property-list-p value)
       (:table
        (unless nested-p
          (:caption "Property list")
          (:thead (:th "Property") (:th "Value")))
        (:tbody
         (loop for (key val) on value by #'cddr
               collect (:tr (:td (format nil "~a" key))
                            (:td (:raw (value->html val t))))))))
      ((trivial-types:association-list-p value)
       (:table
        (unless nested-p
          (:caption "Property list")
          (:thead (:th "Property") (:th "Value")))
        (:tbody
         (dolist (e value)
           (:tr (:td (format nil "~a" (car e)))
                (:td (:raw (value->html (cdr e) t))))))))
      ((trivial-types:proper-list-p value)
       (:ul
        (dotimes (i (length value))
          (:li (:raw (value->html (elt value i) t))))))
      (t (call-next-method)))))

(defmethod value->html ((value array) &optional nested-p)
  (spinneret:with-html-string
    (macrolet ((with-table (&body body)
                 `(:table
                   (unless nested-p
                     (:caption "Array")
                     (:thead
                      (:th :colspan (alex:lastcar (array-dimensions value)) "Elements")))
                   (:tbody ,@body))))
      (case (length (array-dimensions value))
        (1 (with-table
               (:tr
                (loop for e across value
                      collect (:td (:raw (value->html e t)))))))
        (2 (with-table
               (loop with height = (array-dimension value 0)
                     and width = (array-dimension value 1)
                     for y below height
                     collect (:tr (loop for x below width
                                        collect (:td (:raw (value->html (aref value y x) t))))))))
        (otherwise (:raw (call-next-method)))))))

(defmethod value->html ((value sequence) &optional nested-p)
  (declare (ignore nested-p))
  (spinneret:with-html-string
    (:ul
     (dotimes (i (length value))
       (:li (:raw (value->html (elt value i) t)))))))

(defmethod value->html ((value hash-table) &optional nested-p)
  (spinneret:with-html-string
    (alex:if-let ((keys (alex:hash-table-keys value)))
      (:table
       (unless nested-p
         (:caption "Hash-table")
         (:thead (:th "Key") (:th "Value")))
       (:tbody
        (dolist (key keys)
          (:tr (:td (format nil "~a" key))
               (:td (:raw (value->html (gethash key value) t)))))))
      "")))

(defun print-complex-object (value nested-p)
  (if nested-p
      (link-to value)
      (spinneret:with-html-string
        (alex:if-let ((slot-names (mapcar #'closer-mop:slot-definition-name
                                          (closer-mop:class-slots (class-of value)))))
          (:dl
           (dolist (slot-name slot-names)
             (:dt (format nil "~a" slot-name))
             (:dd (:raw (value->html (slot-value value slot-name) t)))))
          ""))))

(defmethod value->html ((value standard-object) &optional nested-p)
  (print-complex-object value nested-p))

(defmethod value->html ((value structure-object) &optional nested-p)
  (print-complex-object value nested-p))
