import requests
import getpass
import re
import os
import subprocess

dir_path = os.path.dirname(os.path.realpath(__file__))
tasks_path = os.path.join(dir_path,'tasks')
if not os.path.exists(tasks_path):
	os.makedirs(tasks_path)
tasksRst_path = os.path.join(dir_path,'tasksRst')
if not os.path.exists(tasksRst_path):
	os.makedirs(tasksRst_path)

nodeRegisterURL = 'https://server.lijiatong1997.com/nodeRegister'
nodeReturnURL = 'https://server.lijiatong1997.com/nodeReturn'
nodeUser = getpass.getuser()
print("Current node user is: ", nodeUser)

def nodeRegister():
	print("Registering to AWS server and waiting for tasks.")
	rawData = requests.get(nodeRegisterURL+'/'+nodeUser, timeout=60)
	fileName = re.findall("filename=\"(.+)\"", rawData.headers['content-disposition'])[0]
	print("Received file: ", fileName, ". Status code:", rawData.status_code)
	with open(os.path.join(tasks_path,fileName), 'wb') as f:
		f.write(rawData.content)
	return fileName
	
def nodeReturn(fileName):
	files = { 'processed_file': open(os.path.join(tasksRst_path,fileName), 'rb') }
	rawData = requests.post(nodeReturnURL+'/'+nodeUser, files=files)
	print("Posted processed file to AWS. Status code: ", rawData.status_code)

def callExecutable(fileName):
	inputFile = os.path.join(tasks_path,fileName)
	outputFile = os.path.join(tasksRst_path,fileName)
	print("\n*****From C++ Program*****\n")
	if inputFile.endswith(".png"):
		# subprocess.run(["srun", "-n1", "-c1", "bin/seq_hist_equalization", inputFile, outputFile, "png"])
		subprocess.run(["srun", "-n1", "--gres=gpu:p100:1", "--partition=debug", "bin/cuda_hist_equalization", inputFile, outputFile, "png"])
	else:
		# subprocess.run(["srun", "-n1", "-c1", "bin/seq_hist_equalization", inputFile, outputFile])
		subprocess.run(["srun", "-n1", "--gres=gpu:p100:1", "--partition=debug", "bin/cuda_hist_equalization", inputFile, outputFile])
	print("\n**************************\n")
	
while True:
	try:
		fn = nodeRegister()
		callExecutable(fn)
		nodeReturn(fn)
	except requests.exceptions.Timeout:
		continue