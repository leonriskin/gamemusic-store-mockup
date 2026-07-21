$base = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress'
$desc = @'
A cheerful Christmas tune full of toy-shop wonder — Santa, bells, piano, and festive sparkle for holiday games, children's apps, cartoons, and seasonal menus.
'@.Trim()

$params = @{
  Title = 'Santa Got A Brand New Toy'
  PreviewMp3 = Join-Path $base 'Music Loops PREVIEW\Santa Got A Brand New Toy PREVIEW.mp3'
  LoopZip = Join-Path $base 'Music Loops WAV\Santa Got A Brand New Toy.zip'
  CoverImage = Join-Path $base 'Music Loops IMG\Final\Santa Got A Brand New Toy.jpg'
  Description = $desc
  Tags = @('Christmas', 'Holidays', 'Children', 'Happy', 'Toys', 'Santa', 'Cartoon', 'Game', 'Cheerful', 'Snow')
  Genre = 'Holidays'
  Bpm = 120
  Duration = '1:29'
  Instruments = 'piano, bells, strings, celeste'
  Category2 = 'Christmas'
}

& (Join-Path $PSScriptRoot 'import-track.ps1') @params
