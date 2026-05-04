package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"os"
	"os/exec"
	"unsafe"

	"github.com/creack/pty"
)

var shellPty *os.File

//export StartShell
func StartShell() {
	cmd := exec.Command("bash")
	var err error
	shellPty, err = pty.Start(cmd)
	if err != nil {
		panic(err)
	}
}

//export WriteToShell
func WriteToShell(input *C.char) {
	goInput := C.GoString(input)
	shellPty.Write([]byte(goInput))
}

//export ReadFromShell
func ReadFromShell(buf *C.char, size C.int) C.int {
	data := make([]byte, int(size))
	n, err := shellPty.Read(data)
	if err != nil {
		return 0
	}
	copy((*[1 << 30]byte)(unsafe.Pointer(buf))[:], data[:n])
	return C.int(n)
}

func main() {}
