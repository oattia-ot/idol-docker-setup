import requests
import os


get_data = {
    'name':'dih.idoldemos.net',
    'FQDN':'dih.idoldemos.net',
    'PORT_INDEX':'9071',
    'scheme':'https',
    'backupLocation':'/data/ICICI_Bank.idx',
    'cert_bundle':'/home/vinay/projects/ssl_nifi/code/content'
}


def restoreBackup(file,fqdn,scheme,port, certbundle):
    URL="{0}://{1}:{2}/DREADD?{3}".format(scheme, fqdn, port, file)
    print("Restoring backup {0}".format(file))
    response = requests.get(URL, verify=certbundle)
    print("Syncing...")
    URL="{0}://{1}:{2}/DRESYNC".format(scheme, fqdn, port)
    response = requests.get(URL, verify=certbundle)



def restoreIndex():
    print("Restoring index from DIH engine " + get_data['name'])
    name=get_data['name']
    fqdn=get_data['FQDN']
    scheme=get_data['scheme']
    port=get_data['PORT_INDEX']
    backupLocation=get_data['backupLocation']
    certbundle=get_data['cert_bundle']
    restoreBackup(backupLocation,fqdn,scheme,port,certbundle)


restoreIndex()