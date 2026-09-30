# Wrap — Creator Project Hub for Mac

> **Status:** In production

**Wrap** is a Mac app for managing a creative project from start to finish. You can plan your shots, set up your editing workspace, and send the finished file to a client without having to jump between a bunch of different apps.

The main idea is to bring three things together: shot planning, workspace setup, and file delivery.

**Who it's for:** photographers, video editors, filmmakers, and motion designers working on personal or client projects.

## The three parts of a project

| Stage   | In-App Features              | What you can do                                                                                                           |
| ------- | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Plan    | Shotlist                     | Make a shot list with reference images, outfits, locations, and notes. Check shots off as you finish them.                |
| Edit    | Dockly, adapted for creators | Open your editor, project file, footage folder, music, and other apps together and put their windows where you want them. |
| Deliver | Export-to-link               | Export to the Wrap disk or drop a finished file into the project and get a client link.                                   |

The main difference is that something like Dropbox is mostly focused on sending the final file. Wrap keeps the project around that file too, so the shots, workspace, and delivery are all connected.

For version 1, Wrap won't have an iPhone app, team accounts, payments, or a Windows version. Everything is free.

## How a project works

A project can go from planning to editing to delivery, all in Wrap.

### Plan

1. Create a new project, give it a name, and optionally add the client's name and email.
2. Add the shots you need, such as Football Field, Parking Lot, Stairwell, Close-up, Full Body, or Low Angle. You can add reference pictures, outfit photos, locations, and notes to each one.
3. When you're shooting, open the shot list and check things off as you get them.

### Edit

4. Go to the project's Workspace tab and add whatever you normally use. For example, Premiere Pro with the project's `.prproj` file, your footage folder, Spotify, or a client email.
5. Arrange the windows how you want them and save the layout.
6. After that, pressing **Launch Workspace** opens everything again. You can launch it from Wrap or the menu bar. **Close Workspace** hides everything when you're finished.

### Deliver

7. Export your finished video to the **Wrap** disk, or just drop the file into the project.
8. Wrap uploads the file while the export is happening. Once the upload finishes, the share link is copied and the delivery gets added to the project.
9. The client opens the link in their browser and downloads the file. You'll get a notification when they do, and the file can then be deleted automatically. Once everything is done, you can mark the project as **Wrapped**.

## Architecture

The planning and workspace parts stay completely on the Mac. The cloud is only used when a file actually needs to be delivered.

![Architecture: 7 parts on the Mac, 4 in the cloud](docs/architecture.png)

* **Project library:** SwiftData stores projects, shots, notes, workspace layouts, and delivery history locally. Reference images are copied into Wrap's own folder, so deleting or moving the original image won't break the project. iCloud syncing can be added later if an iPhone version is made.
* **Workspace launcher:** `NSWorkspace` handles opening apps, files, and folders. Wrap needs Accessibility permission to move and resize windows belonging to other apps. The user only has to grant this once in System Settings.
* **Delivery:** When a file is being uploaded, Wrap asks the API for signed upload URLs and sends the file parts directly to R2. Large files don't have to go through our server first. Once a delivery link is created, it gets saved to the project.

## The virtual disk

The virtual disk is probably the hardest part of Wrap.

For the first version, the plan is to try a **small NFS server running inside the app** and have macOS mount it like a normal network drive. Once the rest of the product is working, this could be replaced with **FSKit**.

The reason for doing it this way is that the disk is what makes Wrap different from just being another file-upload app.

| Option | How it works | Uploads while
