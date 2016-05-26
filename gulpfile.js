var gulp = require('gulp'),
    gutil = require('gulp-util'),
    peg = require('gulp-peg'),
    coffee = require('gulp-coffee'),
    concat = require('gulp-concat'),
    seq = require('run-sequence');

var dest = './dist/';

gulp.task('coffee', function() {
  return gulp.src('./src/aoscript-core.coffee')
      .pipe(coffee().on('error', function(err){
        gutil.log(err.name, err.stack);
        this.emit('end');
      }))
      .pipe(gulp.dest(dest));
});

gulp.task('peg', function() {
  return gulp.src('./src/grammer.pegjs')
      .pipe(peg({ exportVar: 'PEG', cache: true }).on('error', function(err) {
        console.log(err);
        this.emit('end');
      }))
      .pipe(gulp.dest(dest));
})

gulp.task('concat', function() {
  return gulp.src(['./src/intro.js', './dist/grammer.js', './dist/aoscript-core.js', './src/outro.js'])
      .pipe(concat('aoscript.js'))
      .pipe(gulp.dest(dest));
});

gulp.task('build', function(cb) {
  seq(['coffee', 'peg'], 'concat', cb);
});

gulp.task('watch', function() {
  gulp.watch('./src/*', ['build']);
});

gulp.task('default', ['build']);
