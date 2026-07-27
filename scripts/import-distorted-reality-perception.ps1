$base = 'C:\Dropbox\Dropbox\1. My Documents\LEON\Audio Temp Ex\Leon Riskin Music\WordPress'
$desc = @'
A futuristic sci-fi dark track with a strong beat and an engaging bassline. Dark, ominous, and suspenseful.
'@.Trim()

$params = @{
  Title = 'Distorted Reality Perception'
  PreviewMp3 = Join-Path $base 'Music Loops PREVIEW\distorted reality perception PREVIEW.mp3'
  LoopZip = Join-Path $base 'Music Loops WAV\distorted reality perception long loop.zip'
  CoverImage = Join-Path $base 'Music Loops IMG\Final\Distorted Reality Perception.jpg'
  Description = $desc
  Tags = @(
    'Menu', 'Level', 'Gameplay', 'Cyberpunk', 'Badass', 'Dark', 'Ominous', 'Dangerous', 'Mystery',
    'Bad', 'Scary', 'Horror', 'Futuristic', 'Scifi', 'Science', 'Apocalyptic', 'Action', 'Beat',
    'Serious', 'Underscore', 'Future', 'Retro', 'Electronic', 'Techno', 'Cinematic'
  )
  Genre = 'Cinematic'
  Bpm = 87
  Duration = '1:44'
  Instruments = 'synth, bass, drums, electronic'
  Category2 = 'Horror'
}

& (Join-Path $PSScriptRoot 'import-track.ps1') @params
