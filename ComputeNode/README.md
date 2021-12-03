## Use Instruction in HPC

- Log into High Proformance Computing cluster
- Run `module  purge` and `module  load  gcc /8.3.0  cuda /10.1.243 python`
- In the `bin` folder, compile the program `nvcc -o cuda_hist_equalization -O3 cuda_hist_qualization.cu`
- In root folder, run the nodecompute.py `python3 nodeCompute.py`

## Use Instruction in PC

- Make sure requests package is installed `pip install requests`
- In the `bin` folder, compile the program `g++ -o seq_hist_equalization -O3 seq_hist_qualization.cu`
- In root folder, run the personalNode.py `python3 personalNode.py`

Acturally you can change the image processing program as you want, just make sure call it in the right way through subprocess.run() funtion in the python script.