### Building the Image on macOS via Docker

> These steps assume you have Docker toolchain installed on your Mac and that you have already cloned the repository into `microlab-image/`.

1. **Build the "builder" image**  
   From the project root (where `Dockerfile.builder` lives), run:
   ```bash
   docker build -f Dockerfile.builder -t microlab-image-builder .
   ```

2. **Register ARM compiler**
   ```bash
   docker run --rm --privileged tonistiigi/binfmt --install all
   ```

3. **Run the build inside Docker**
   This will mount your workspace into the container, create loop devices, mount partitions, and invoke the standard build script. The `--privileged` flag is required so the container can manage loopback devices and mounts.

   ```bash
   docker run --rm --privileged -v "$(pwd)":/workspace microlab-image-builder \
        bash -lc "cd /workspace && bash scripts/build-image.sh"   
   ```

3. **Retrieve your image**
   When the container finishes, you’ll find:

   ```
   microlab-image/build/raspios-microlab.img
   ```

   ready to flash to an SD card.

> **Tip**: If you’d rather limit privileges, you can replace `--privileged` with
> `--cap-add=SYS_ADMIN --cap-add=NET_ADMIN -v /dev:/dev`
> but you’ll need to rebuild the container only when build-time dependencies change.
