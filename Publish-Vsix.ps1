$PersonalAccessToken = 'mo5enp4j7iac4wmuoehfquuxmdrykwgihjkqugqyvee3wq2whjeq'
$publisher = 'IncrementalGroup'

$vsixFile = Get-ChildItem -Filter *.vsix -Recurse
if($vsixFile.Count -eq 1)
{
    tfx extension publish --publisher $publisher --token $PersonalAccessToken --vsix $vsixFile.Fullname
}